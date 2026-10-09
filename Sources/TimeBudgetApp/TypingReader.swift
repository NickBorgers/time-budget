import AppKit
import ApplicationServices
import TimeBudgetCore

/// Reads the focused text field of the frontmost app, for `TypingTracker`.
///
/// This is not a keystroke reader. It needs no Input Monitoring permission,
/// and it sees only what the field shows through Accessibility. A password
/// field shows nothing, and the reader skips it.
enum TypingReader {
  /// How often the app looks at the focused field.
  static let interval: TimeInterval = 5
  /// A field larger than this, such as a long document or a terminal
  /// buffer, is not compared: the comparison would cost too much CPU.
  static let maxFieldLength = 100_000

  /// Nil when there is no readable field, or when the app or window is excluded.
  @MainActor
  static func snapshot(exclude: ExcludeList) async -> FieldSnapshot? {
    guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else {
      return nil
    }
    let name = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
    if exclude.excludesApp(name: name, bundleID: app.bundleIdentifier) { return nil }
    let pid = app.processIdentifier
    let keyPressed = secondsSinceKeyPress() <= interval + 1
    return await Task.detached {
      read(pid: pid, exclude: exclude, keyPressed: keyPressed)
    }.value
  }

  /// Seconds since the last key press. This reads only the time, not the key,
  /// and needs no Input Monitoring permission.
  static func secondsSinceKeyPress() -> Double {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
  }

  private static func read(pid: pid_t, exclude: ExcludeList, keyPressed: Bool) -> FieldSnapshot? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, AccessibilityText.timeoutSeconds)

    // The same checks as the screen reader, before any text is read.
    guard let window: AXUIElement = AccessibilityText.value(app, kAXFocusedWindowAttribute)
    else { return nil }
    let title: String? = AccessibilityText.value(window, kAXTitleAttribute)
    if exclude.excludesWindow(title: title, host: nil) { return nil }
    if !exclude.hosts.isEmpty {
      // A page with an unknown address could be an excluded site.
      guard let identity = AccessibilityText.identity(pid: pid),
        !identity.hosts.contains(where: { exclude.excludesWindow(title: title, host: $0) })
      else { return nil }
    }

    guard let field: AXUIElement = AccessibilityText.value(app, kAXFocusedUIElementAttribute)
    else { return nil }
    let role: String? = AccessibilityText.value(field, kAXRoleAttribute)
    let subrole: String? = AccessibilityText.value(field, kAXSubroleAttribute)
    // Never read a password field.
    if role == (kAXSecureTextFieldSubrole as String)
      || subrole == (kAXSecureTextFieldSubrole as String)
    {
      return nil
    }
    guard let value: String = AccessibilityText.value(field, kAXValueAttribute),
      value.utf16.count <= maxFieldLength
    else { return nil }
    return FieldSnapshot(fieldID: "\(pid)-\(CFHash(field))", value: value, keyPressed: keyPressed)
  }
}
