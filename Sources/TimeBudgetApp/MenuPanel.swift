import SwiftUI
import TimeBudgetCore

/// The panel that opens from the menu bar item.
struct MenuPanel: View {
  @Bindable var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let problem = model.problem {
        HStack(alignment: .top) {
          Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
          Text(problem).font(.callout).fixedSize(horizontal: false, vertical: true)
          Spacer()
          Button("OK") { model.dismissProblem() }
        }
        Divider()
      }

      detected
      Divider()

      HStack {
        Text(model.countsModelLabel ? "Your label (not counted)" : "What are you working on?")
          .font(.headline)
          .help(
            model.countsModelLabel
              ? "The classifier's label counts. Your selection is stored next to it, to measure how often the two agree."
              : "Your selection counts.")
        Spacer()
        Button("Edit…") { SettingsWindowController.show() }
          .help("Add, rename, remove, and budget your allocations")
      }
      VStack(spacing: 6) {
        ForEach(model.state.allocations) { allocation in
          AllocationRow(
            allocation: allocation, status: model.status(for: allocation),
            selected: model.state.selectedAllocationID == allocation.id
          ) { model.select(allocation) }
        }
        UnassignedRow(selected: model.state.selectedAllocationID == nil) { model.select(nil) }
      }

      Divider()
      pauseControls
      Divider()
      lastCapture
      Divider()
      permissions
      Divider()

      HStack {
        Button("Settings…") { SettingsWindowController.show() }
        Button("Capture log") { model.openDataFolder() }
        Spacer()
        Button("Quit") { NSApplication.shared.terminate(nil) }
      }
    }
    .padding(14)
    .frame(width: 380)
    .onAppear { model.refreshPermissions() }
  }

  /// The classifier's last label and its reason (spec "What the user sees as
  /// the reason").
  private var detected: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text("Detected").font(.headline)
        Spacer()
        Text(modelLine).font(.caption).foregroundStyle(.secondary)
      }
      if let decision = model.lastDecision {
        Text(labelName(decision.label) + confidenceText(decision.confidence))
          .fontWeight(.semibold)
        Text(reason(decision)).font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text("No minute classified yet.").font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private var modelLine: String {
    switch model.modelStatus {
    case .notBundled: "No model in this build"
    case .loading: "Loading the model…"
    case .ready(let name): model.countsModelLabel ? name : "\(name), not counted"
    case .failed: "The model did not load"
    }
  }

  private func labelName(_ label: SliceLabel) -> String {
    switch label {
    case .allocation(let id):
      model.state.allocations.first { $0.id == id }?.name ?? "Removed allocation"
    case .unassigned: "Unassigned"
    case .idle: "Idle"
    }
  }

  private func confidenceText(_ confidence: Double?) -> String {
    confidence.map { " · \(Int(($0 * 100).rounded()))%" } ?? ""
  }

  private func reason(_ decision: SliceDecision) -> String {
    var evidence: [String] = []
    if let e = model.lastRecord?.evidence, model.lastRecord?.trigger == .minute {
      evidence.append(e.appName)
      if let title = e.windowTitle, !title.isEmpty { evidence.append(title) }
    }
    let why: String
    switch decision.method {
    case .idle: why = "No input for more than 5 minutes."
    case .unchanged: why = "Same screen as the minute before."
    case .rule(let id):
      if let rule = model.state.pinnedRules.first(where: { $0.id == id }) {
        why = "Rule: \(rule.conditionText)."
      } else {
        why = "A pinned rule."
      }
    case .model:
      let top = (decision.options ?? []).sorted { $0.probability > $1.probability }.prefix(2)
      let scores = top.map { "\($0.name) \(Int(($0.probability * 100).rounded()))%" }
      why =
        decision.label == .unassigned && top.first?.label != .unassigned
        ? "Below the 60% threshold: " + scores.joined(separator: ", ") + "."
        : "Model: " + scores.joined(separator: ", ") + "."
    case .noModel:
      why =
        model.state.allocations.isEmpty ? "No allocations to choose from." : "No model decision."
    }
    return (evidence + [why]).joined(separator: " · ")
  }

  @ViewBuilder private var pauseControls: some View {
    if model.state.isPaused(at: Date()) {
      HStack {
        Image(systemName: "pause.circle.fill")
        if model.state.pausedUntil == .distantFuture {
          Text("Paused until you resume")
        } else if let until = model.state.pausedUntil {
          Text("Paused until \(until.formatted(date: .omitted, time: .shortened))")
        }
        Spacer()
        Button("Resume") { model.resume() }
      }
    } else {
      HStack {
        Text("Pause")
        Spacer()
        Button("15 min") { model.pause(minutes: 15) }
        Button("1 hour") { model.pause(minutes: 60) }
        Button("Until I resume") { model.pause(minutes: nil) }
      }
    }
  }

  private var lastCapture: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Last capture").font(.subheadline.bold())
      if let record = model.lastRecord {
        Text(record.time.formatted(date: .omitted, time: .standard))
          .font(.caption).foregroundStyle(.secondary)
        if let title = record.evidence.windowTitle, !title.isEmpty {
          Text(title).font(.caption).lineLimit(1).truncationMode(.middle)
        }
      }
      Text(model.lastNote).font(.caption).foregroundStyle(.secondary)
    }
  }

  private var permissions: some View {
    VStack(alignment: .leading, spacing: 4) {
      PermissionRow(
        name: "Accessibility", purpose: "Window titles and visible text",
        allowed: model.accessibilityAllowed, action: model.requestAccessibility)
      PermissionRow(
        name: "Screen Recording",
        purpose: model.screenRecordingAllowed
          ? "Text recognition fallback" : "Text recognition. After granting, quit and reopen.",
        allowed: model.screenRecordingAllowed, action: model.requestScreenRecording)
      PermissionRow(
        name: "Notifications", purpose: "Budget alerts",
        allowed: model.notificationsAllowed, action: nil)
    }
  }
}

private struct AllocationRow: View {
  let allocation: Allocation
  let status: BudgetStatus
  let selected: Bool
  let choose: () -> Void

  var body: some View {
    Button(action: choose) {
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Image(systemName: selected ? "largecircle.fill.circle" : "circle")
          Text(allocation.name).fontWeight(selected ? .semibold : .regular)
          Spacer()
          Text(
            "\(TextTools.duration(minutes: status.usedMinutes)) of \(TextTools.duration(minutes: status.budgetMinutes))"
          )
          .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        ProgressView(
          value: Double(min(status.usedMinutes, status.budgetMinutes)),
          total: Double(max(status.budgetMinutes, 1))
        )
        .tint(barColor)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var barColor: Color {
    if status.hasReached(.spent) { return .red }
    if status.hasReached(.warning) { return .orange }
    return .accentColor
  }
}

private struct UnassignedRow: View {
  let selected: Bool
  let choose: () -> Void

  var body: some View {
    Button(action: choose) {
      HStack {
        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
        Text("Unassigned (not counted)").foregroundStyle(.secondary)
        Spacer()
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

private struct PermissionRow: View {
  let name: String
  let purpose: String
  let allowed: Bool
  let action: (() -> Void)?

  var body: some View {
    HStack {
      Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle")
        .foregroundStyle(allowed ? .green : .red)
      VStack(alignment: .leading, spacing: 0) {
        Text(name).font(.callout)
        Text(purpose).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if !allowed, let action {
        Button("Grant…", action: action)
      }
    }
  }
}
