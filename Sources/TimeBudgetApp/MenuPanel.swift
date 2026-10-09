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

      Text("What are you working on?").font(.headline)
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
        SettingsLink { Text("Settings…") }
          // A menu bar app is not active, so its window would open behind others.
          .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
        Button("Capture log") { model.openDataFolder() }
        Spacer()
        Button("Quit") { NSApplication.shared.terminate(nil) }
      }
    }
    .padding(14)
    .frame(width: 380)
    .onAppear { model.refreshPermissions() }
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
