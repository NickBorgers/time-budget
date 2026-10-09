import AppKit
import ApplicationServices
import ScreenCaptureKit
import TimeBudgetCore
import Vision

/// Reads the evidence for one slice from the frontmost window (spec F2).
///
/// It reads in this order, and checks the exclude list between the steps, so it
/// reads nothing more from an excluded app or window:
/// 1. The app name and bundle identifier, from `NSWorkspace`.
/// 2. The window title and the browser host, from the Accessibility API.
/// 3. The visible text, from the Accessibility API.
/// 4. Text recognition on a screenshot, when screen recording is permitted.
enum ScreenReader {
  struct Options: Sendable {
    var exclude: ExcludeList
    /// Run text recognition even when the Accessibility API returned text.
    var alwaysRecognizeText: Bool
  }

  /// Nil means the app or window is excluded, or no app is frontmost.
  @MainActor
  static func read(options: Options) async -> SliceEvidence? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let name = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
    let bundleID = app.bundleIdentifier
    if options.exclude.excludesApp(name: name, bundleID: bundleID) { return nil }
    let pid = app.processIdentifier
    let idle = secondsSinceInput()

    var evidence = SliceEvidence(appName: name, bundleID: bundleID, secondsSinceInput: idle)
    guard AXIsProcessTrusted() else { return evidence }

    let exclude = options.exclude
    // Accessibility calls can block on a busy app. Run them off the main thread.
    let window = await Task.detached { AccessibilityText.read(pid: pid, exclude: exclude) }.value
    guard let window else { return nil }
    evidence.windowTitle = window.title
    evidence.host = window.host
    evidence.visibleText = window.text
    evidence.textSource = window.text.isEmpty ? .none : .accessibility

    guard window.text.isEmpty || options.alwaysRecognizeText else { return evidence }
    guard window.mayRecognizeText else {
      evidence.recognitionNote = "no focused window"
      return evidence
    }
    guard CGPreflightScreenCaptureAccess() else {
      evidence.recognitionNote = "no Screen Recording permission"
      return evidence
    }
    guard let identity = window.identity else {
      evidence.recognitionNote = "focused window has no frame, or its tree was not fully read"
      return evidence
    }
    switch await TextRecognition.read(pid: pid, identity: identity) {
    case .success(let recognized):
      evidence.recognizedText = recognized
      if evidence.textSource == .none, !recognized.isEmpty {
        evidence.visibleText = recognized
        evidence.textSource = .textRecognition
      }
    case .failure(let reason):
      evidence.recognitionNote = reason.description
    }
    return evidence
  }

  /// Seconds since the last keyboard, mouse or trackpad event. This reads only
  /// the time. It does not need the Input Monitoring permission.
  static func secondsSinceInput() -> Double {
    // kCGAnyInputEventType is ~0 in C.
    guard let any = CGEventType(rawValue: ~0) else { return 0 }
    return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
  }
}

/// The parts of the focused window that the Accessibility API exposes.
enum AccessibilityText {
  struct Window: Sendable {
    var title: String?
    var host: String?
    var text: String
    /// The focused window on screen, in global coordinates with the origin at
    /// the top left. Text recognition uses it to find the same window.
    var frame: CGRect?
    /// What the exclude list checked. Text recognition compares it again just
    /// before and after the screenshot.
    var identity: Identity?
    /// False when the focused window is unknown. Text recognition then has no
    /// title to check against the exclude list, so it must not run.
    var mayRecognizeText = true
  }

  /// The parts of the focused window that the exclude list checks.
  struct Identity: Equatable, Sendable {
    var title: String?
    var frame: CGRect
    var hosts: [String]
  }

  /// Reads the identity of the focused window again, with no text. Nil when
  /// any read fails or is inconclusive.
  static func identity(pid: pid_t) -> Identity? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, timeoutSeconds)
    guard let window: AXUIElement = value(app, kAXFocusedWindowAttribute),
      let frame = frame(of: window)
    else { return nil }
    var rawTitle: CFTypeRef?
    let title: String?
    switch AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &rawTitle) {
    case .success: title = rawTitle as? String
    case .noValue, .attributeUnsupported: title = nil
    default: return nil
    }
    var finder = WebAreaFinder()
    finder.walk(window, depth: 0)
    guard finder.conclusive else { return nil }
    return Identity(title: title, frame: frame, hosts: finder.hosts)
  }

  /// Limits that keep one read short on a window with a very large tree.
  static let maxElements = 4_000
  static let maxDepth = 60
  static let timeoutSeconds: Float = 0.25

  /// Nil means the window is excluded by its title or host.
  static func read(pid: pid_t, exclude: ExcludeList) -> Window? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, timeoutSeconds)
    // Chrome and Electron apps (Slack, VS Code) build their accessibility tree
    // only when they are asked to. This attribute asks them.
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

    guard let window: AXUIElement = value(app, kAXFocusedWindowAttribute) else {
      return Window(title: nil, host: nil, text: "", mayRecognizeText: false)
    }
    var rawTitle: CFTypeRef?
    let title: String?
    switch AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &rawTitle) {
    case .success: title = rawTitle as? String
    case .noValue, .attributeUnsupported: title = nil
    // A title that failed to read could be a private window.
    default: return nil
    }
    if exclude.excludesWindow(title: title, host: nil) { return nil }

    // Pass 1 reads only roles and web page addresses, no text.
    var finder = WebAreaFinder()
    finder.walk(window, depth: 0)
    if finder.hosts.contains(where: { exclude.excludesWindow(title: title, host: $0) }) {
      return nil
    }
    if exclude.excludesWindow(title: title, host: nil) { return nil }
    // A page whose address is unknown could be an excluded site. When the user
    // has listed sites, read nothing unless pass 1 saw the whole tree and
    // every page in it had an address.
    if !exclude.hosts.isEmpty, !finder.conclusive || finder.pagesWithoutAddress > 0 {
      return nil
    }

    // Pass 2 reads the text.
    let windowFrame = frame(of: window)
    var walker = Walker(windowFrame: windowFrame)
    walker.walk(window, depth: 0)
    return Window(
      title: title, host: finder.hosts.first, text: TextTools.joinVisibleText(walker.pieces),
      frame: windowFrame,
      identity: windowFrame.flatMap { frame in
        finder.conclusive ? Identity(title: title, frame: frame, hosts: finder.hosts) : nil
      })
  }

  /// Finds every web area and its address. Reads no text.
  private struct WebAreaFinder {
    var hosts: [String] = []
    var pagesWithoutAddress = 0
    /// False when a limit or an Accessibility error stopped the walk early.
    var conclusive = true
    var visited = 0

    mutating func walk(_ element: AXUIElement, depth: Int) {
      guard conclusive else { return }
      guard depth <= AccessibilityText.maxDepth, visited < AccessibilityText.maxElements else {
        conclusive = false
        return
      }
      visited += 1
      var raw: CFTypeRef?
      guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &raw) == .success,
        let role = raw as? String
      else {
        // An element with no readable role could be a web page.
        conclusive = false
        return
      }
      if role == "AXWebArea" {
        let url: URL? = AccessibilityText.value(element, "AXURL")
        if let host = url?.host { hosts.append(host) } else { pagesWithoutAddress += 1 }
      }
      guard let children = AccessibilityText.children(of: element) else {
        conclusive = false
        return
      }
      for child in children { walk(child, depth: depth + 1) }
    }
  }

  private struct Walker {
    let windowFrame: CGRect?
    var pieces: [String] = []
    var visited = 0
    var characters = 0
    var stopped = false

    mutating func walk(_ element: AXUIElement, depth: Int) {
      guard !stopped, depth <= AccessibilityText.maxDepth else { return }
      visited += 1
      if visited > AccessibilityText.maxElements
        || characters > TextTools.visibleTextLimit * 2
      {
        stopped = true
        return
      }
      let role: String? = AccessibilityText.value(element, kAXRoleAttribute)
      let subrole: String? = AccessibilityText.value(element, kAXSubroleAttribute)
      // Never read a password field.
      if subrole == (kAXSecureTextFieldSubrole as String) { return }

      if let role, Self.textRoles.contains(role), isOnScreen(element) {
        let text: String? =
          AccessibilityText.value(element, kAXValueAttribute)
          ?? AccessibilityText.value(element, kAXTitleAttribute)
        if let text, !text.isEmpty {
          pieces.append(text)
          characters += text.count
        }
      }
      let children: [AXUIElement] = AccessibilityText.value(element, kAXChildrenAttribute) ?? []
      for child in children { walk(child, depth: depth + 1) }
    }

    static let textRoles: Set<String> = [
      kAXStaticTextRole, kAXTextAreaRole, kAXTextFieldRole, "AXHeading",
    ]

    /// Drops text that is scrolled out of the window, such as old chat history.
    func isOnScreen(_ element: AXUIElement) -> Bool {
      guard let windowFrame, let own = AccessibilityText.frame(of: element) else { return true }
      return own.intersects(windowFrame)
    }
  }

  static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
      let raw
    else { return nil }
    if T.self == AXUIElement.self {
      guard CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
      return (raw as! T)
    }
    return raw as? T
  }

  /// The children of `element`, an empty list when it has none, or nil when
  /// the Accessibility API failed.
  static func children(of element: AXUIElement) -> [AXUIElement]? {
    var raw: CFTypeRef?
    switch AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) {
    case .success: return raw as? [AXUIElement]
    case .noValue, .attributeUnsupported: return []
    default: return nil
    }
  }

  static func frame(of element: AXUIElement) -> CGRect? {
    guard let position: AXValue = axValue(element, kAXPositionAttribute),
      let size: AXValue = axValue(element, kAXSizeAttribute)
    else { return nil }
    var point = CGPoint.zero
    var extent = CGSize.zero
    guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &extent)
    else { return nil }
    return CGRect(origin: point, size: extent)
  }

  private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
      let raw, CFGetTypeID(raw) == AXValueGetTypeID()
    else { return nil }
    return (raw as! AXValue)
  }
}

/// On-device text recognition on a screenshot of the frontmost window. The
/// screenshot stays in memory and is never written to disk.
enum TextRecognition {
  struct Skipped: Error, CustomStringConvertible {
    let description: String
  }

  /// Two frames closer than this, in points, are the same window.
  static let frameTolerance: CGFloat = 2

  static func read(pid: pid_t, identity: AccessibilityText.Identity) async -> Result<
    String, Skipped
  > {
    let frame = identity.frame
    // The user can switch windows during the async steps below. Check the
    // focused window again just before and just after the screenshot. If it
    // changed, the screenshot may show a window that the exclude list did
    // not check, so it is thrown away.
    @Sendable func unchanged() async -> Bool {
      await Task.detached { AccessibilityText.identity(pid: pid) }.value == identity
    }
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(
        true, onScreenWindowsOnly: true)
      let candidates = content.windows.filter {
        $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 50
      }
      // Only the focused window, found by its position and size: its title
      // passed the exclude list. Apps report different titles to the two
      // APIs (Chrome does), so titles do not identify it. Two windows of the
      // app in the same place are ambiguous, so the app reads neither.
      let matches = candidates.filter { sameFrame($0.frame, frame) }
      guard matches.count == 1, let window = matches.first else {
        return .failure(
          Skipped(
            description:
              "\(matches.count) windows match the focused window frame, of \(candidates.count) on screen"
          ))
      }

      guard await unchanged() else {
        return .failure(Skipped(description: "focused window changed before the screenshot"))
      }
      let filter = SCContentFilter(desktopIndependentWindow: window)
      let config = SCStreamConfiguration()
      let scale = CGFloat(filter.pointPixelScale)
      config.width = Int(window.frame.width * scale)
      config.height = Int(window.frame.height * scale)
      config.showsCursor = false
      let image = try await SCScreenshotManager.captureImage(
        contentFilter: filter, configuration: config)
      guard await unchanged() else {
        return .failure(Skipped(description: "focused window changed during the screenshot"))
      }
      return .success(try await Task.detached { try recognize(image) }.value)
    } catch {
      return .failure(Skipped(description: "failed: \(error.localizedDescription)"))
    }
  }

  static func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) <= frameTolerance && abs(a.minY - b.minY) <= frameTolerance
      && abs(a.width - b.width) <= frameTolerance && abs(a.height - b.height) <= frameTolerance
  }

  private static func recognize(_ image: CGImage) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    try VNImageRequestHandler(cgImage: image).perform([request])
    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    return TextTools.joinVisibleText(lines)
  }
}
