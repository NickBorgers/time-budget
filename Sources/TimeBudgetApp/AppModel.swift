import AppKit
import ApplicationServices
import Observation
import TimeBudgetCore

/// The running app: the saved state, the capture timer, and the alerts.
///
/// In this version the user is the classifier. The allocation selected in the
/// menu bar is the label of every slice, except an idle slice.
@MainActor
@Observable
final class AppModel {
  private(set) var state = SavedState()
  private(set) var lastRecord: SliceRecord?
  /// One line about the last capture, for the panel.
  private(set) var lastNote = "No capture yet."
  /// A problem the user must know about, such as a file that did not save.
  private(set) var problem: String?
  private(set) var accessibilityAllowed = false
  private(set) var screenRecordingAllowed = false
  private(set) var notificationsAllowed = false
  /// Changes every minute, so time-based text in the views refreshes.
  private(set) var now = Date()

  let storage: Storage
  private let notifier = Notifier()
  private let calendar = Calendar.autoupdatingCurrent
  private var timer: Timer?
  private var capturing = false
  private var appSwitchTask: Task<Void, Never>?
  /// Minutes that arrived while a read was running, each with the label the
  /// user had selected at that minute.
  private var pendingMinutes: [(time: Date, selected: SliceLabel)] = []
  /// Changes on pause and on "Delete all data", to discard reads in flight.
  private var generation = 0
  private var started = false

  init(storage: Storage = .standard) {
    self.storage = storage
  }

  // MARK: - Start

  func start() {
    guard !started else { return }
    started = true
    do {
      try storage.prepare()
    } catch {
      problem = "Cannot create the data folder: \(error.localizedDescription)"
    }
    switch storage.loadState() {
    case .loaded(let saved): state = saved
    case .fresh: save()
    case .unreadable(let url, let error):
      problem =
        "The saved state did not load (\(error.localizedDescription)). It moved to \(url.lastPathComponent). The app started fresh."
      save()
    }
    deleteExpiredLogs(now: Date())
    notifier.start()
    refreshPermissions()
    MainWindow.show(model: self)

    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.scheduleAppSwitchCapture() }
    }
    // The user grants permissions in System Settings, then comes back.
    NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshPermissions() }
    }
    let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.capture(.minute) }
    }
    timer.tolerance = 5
    // .common keeps the timer firing while a menu is open.
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  // MARK: - Capture

  /// macOS reports the app switch before the new app has a focused window.
  /// Reading at once finds no window, so wait a moment. A quick run of switches
  /// gives one read, of the app the user stopped on.
  private func scheduleAppSwitchCapture() {
    appSwitchTask?.cancel()
    appSwitchTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      self?.capture(.appSwitch)
    }
  }

  func capture(
    _ trigger: SliceTrigger, at time: Date = Date(), selected: SliceLabel? = nil
  ) {
    now = Date()
    if state.isPaused(at: time) {
      lastNote = "Paused. Nothing captured."
      return
    }
    if state.pausedUntil != nil {
      state.pausedUntil = nil
      save()
    }
    // One read at a time. A minute that arrives during a read waits and runs
    // next, so it still counts. An app switch during a read is skipped: it
    // only adds evidence, not time.
    // Take the label now. The user can change the selection during the read,
    // and the new selection belongs to later minutes.
    let selected = selected ?? state.selectedLabel
    guard !capturing else {
      if trigger == .minute { pendingMinutes.append((time, selected)) }
      return
    }
    capturing = true
    let generation = self.generation
    let options = ScreenReader.Options(
      exclude: state.exclude,
      // Text recognition costs CPU. Run it once a minute, not at each switch.
      alwaysRecognizeText: trigger == .minute && state.recognizeTextEveryMinute)
    Task {
      let evidence = await ScreenReader.read(options: options)
      self.capturing = false
      // Pause and "Delete all data" change the generation. A read that started
      // before them is thrown away.
      if generation == self.generation {
        await self.finishCapture(evidence, trigger: trigger, time: time, selected: selected)
      }
      if !self.pendingMinutes.isEmpty {
        let next = self.pendingMinutes.removeFirst()
        self.capture(.minute, at: next.time, selected: next.selected)
      }
    }
  }

  private func finishCapture(
    _ evidence: SliceEvidence?, trigger: SliceTrigger, time: Date, selected: SliceLabel
  ) async {
    refreshPermissions()
    let rules = SliceRules(exclude: state.exclude)
    guard let evidence, let label = rules.label(for: evidence, selected: selected)
    else {
      lastRecord = nil
      lastNote = "Excluded window. Nothing stored."
      return
    }
    let record = SliceRecord(
      time: time, trigger: trigger, label: label, userLabel: selected, evidence: evidence)
    lastRecord = record
    lastNote = describe(record)
    do {
      try storage.append(record, calendar: calendar)
    } catch {
      problem = "The capture log did not save: \(error.localizedDescription)"
    }
    guard trigger == .minute else { return }
    deleteExpiredLogs(now: time)

    guard case .allocation(let id) = label,
      let allocation = state.allocations.first(where: { $0.id == id })
    else { return }
    let reached = state.ledger.add(to: allocation, at: time, calendar: calendar)
    let status = state.ledger.status(for: allocation, at: time, calendar: calendar)
    let key = state.ledger.key(for: allocation, at: time, calendar: calendar)
    save()
    for threshold in reached {
      let delivered = await notifier.announce(
        threshold, for: allocation, status: status, key: key)
      // An alert that did not reach the user is not spent: the next minute
      // tries again, for example after the user allows notifications.
      if !delivered {
        state.ledger.withdraw(threshold, for: key)
        save()
      }
    }
  }

  private func deleteExpiredLogs(now: Date) {
    do {
      try storage.deleteExpiredLogs(now: now, calendar: calendar)
    } catch {
      problem =
        "Old capture logs were not deleted: \(error.localizedDescription). The app tries again each minute."
    }
  }

  private func describe(_ record: SliceRecord) -> String {
    let e = record.evidence
    var parts = [e.appName]
    if let host = e.host { parts.append(host) }
    switch e.textSource {
    case .accessibility: parts.append("\(e.visibleText.count) chars (Accessibility)")
    case .textRecognition: parts.append("\(e.visibleText.count) chars (text recognition)")
    case .none: parts.append("no text")
    }
    if let recognized = e.recognizedText, e.textSource == .accessibility {
      parts.append("\(recognized.count) chars recognized")
    }
    if record.label == .idle { parts.append("idle") }
    return parts.joined(separator: " · ")
  }

  // MARK: - User actions

  func select(_ allocation: Allocation?) {
    state.selectedAllocationID = allocation?.id
    save()
  }

  func pause(minutes: Int?) {
    generation += 1
    pendingMinutes = []
    state.pausedUntil = minutes.map { Date().addingTimeInterval(Double($0) * 60) } ?? .distantFuture
    lastNote = "Paused. Nothing captured."
    save()
  }

  func resume() {
    state.pausedUntil = nil
    save()
    capture(.appSwitch)
  }

  func update(_ allocation: Allocation) {
    guard let index = state.allocations.firstIndex(where: { $0.id == allocation.id }) else {
      return
    }
    state.allocations[index] = allocation
    save()
  }

  func addAllocation() {
    state.allocations.append(
      Allocation(name: "New allocation", descriptionText: "", budgetMinutes: 60, period: .week))
    save()
  }

  /// Removes the allocation from the list. Its minutes stay in the ledger.
  func remove(_ allocation: Allocation) {
    state.allocations.removeAll { $0.id == allocation.id }
    if state.selectedAllocationID == allocation.id { state.selectedAllocationID = nil }
    save()
  }

  func setExclude(_ exclude: ExcludeList) {
    state.exclude = exclude
    save()
  }

  func setRecognizeTextEveryMinute(_ on: Bool) {
    state.recognizeTextEveryMinute = on
    save()
  }

  func deleteAllData() {
    generation += 1
    pendingMinutes = []
    do {
      try storage.deleteEverything()
      state = SavedState()
      lastRecord = nil
      lastNote = "All data deleted."
      save()
    } catch {
      problem = "Delete failed: \(error.localizedDescription)"
    }
  }

  func dismissProblem() { problem = nil }

  // MARK: - Status

  func status(for allocation: Allocation) -> BudgetStatus {
    state.ledger.status(for: allocation, at: now, calendar: calendar)
  }

  /// The menu bar text, for example `Partner te… 1h 10m`. The name is cut
  /// short, because a long label can hide behind the camera notch.
  var menuBarTitle: String {
    if state.isPaused(at: now) { return "Paused" }
    guard let allocation = state.selectedAllocation else { return "–" }
    let status = status(for: allocation)
    let name =
      allocation.name.count > 12 ? allocation.name.prefix(10) + "…" : Substring(allocation.name)
    if status.hasReached(.spent) { return "\(name) spent" }
    return "\(name) \(TextTools.duration(minutes: status.remainingMinutes))"
  }

  var menuBarSymbol: String {
    if state.isPaused(at: now) { return "pause.circle" }
    guard let allocation = state.selectedAllocation else { return "questionmark.circle" }
    return status(for: allocation).hasReached(.spent) ? "exclamationmark.triangle.fill" : "timer"
  }

  /// Permissions can be lost at any time: macOS asks again for screen recording
  /// each month. Read them again at each capture.
  func refreshPermissions() {
    accessibilityAllowed = AXIsProcessTrusted()
    screenRecordingAllowed = CGPreflightScreenCaptureAccess()
    Task { self.notificationsAllowed = await notifier.isAllowed() }
  }

  func requestAccessibility() {
    // The value of kAXTrustedCheckOptionPrompt. Swift 6 rejects the global var.
    let key = "AXTrustedCheckOptionPrompt"
    _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
  }

  func requestScreenRecording() {
    _ = CGRequestScreenCaptureAccess()
  }

  func openDataFolder() {
    NSWorkspace.shared.open(storage.folder)
  }

  private func save() {
    do {
      try storage.save(state)
    } catch {
      problem = "The state did not save: \(error.localizedDescription)"
    }
  }
}
