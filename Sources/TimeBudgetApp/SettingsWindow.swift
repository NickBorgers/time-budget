import SwiftUI
import TimeBudgetCore

/// Allocations (spec F1), the exclude list (spec F8), and capture options.
struct SettingsWindow: View {
  @Bindable var model: AppModel
  @State private var confirmDelete = false

  var body: some View {
    TabView {
      allocations.tabItem { Label("Allocations", systemImage: "chart.bar") }
      privacy.tabItem { Label("Privacy", systemImage: "hand.raised") }
    }
    .padding()
    .frame(minWidth: 560, minHeight: 460)
  }

  private var allocations: some View {
    VStack(alignment: .leading) {
      List {
        ForEach(model.state.allocations) { allocation in
          AllocationEditor(allocation: allocation, save: model.update, remove: model.remove)
        }
      }
      HStack {
        Button("Add allocation") { model.addAllocation() }
        Spacer()
        Text("Removing an allocation keeps its minutes in the ledger.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private var privacy: some View {
    Form {
      Section("Never read these (one per line, case ignored)") {
        ListEditor(
          title: "Apps: name or bundle identifier", lines: model.state.exclude.apps
        ) { lines in
          var exclude = model.state.exclude
          exclude.apps = lines
          model.setExclude(exclude)
        }
        ListEditor(
          title: "Websites: host, also matches subdomains", lines: model.state.exclude.hosts
        ) { lines in
          var exclude = model.state.exclude
          exclude.hosts = lines
          model.setExclude(exclude)
        }
        ListEditor(
          title: "Window titles that contain", lines: model.state.exclude.titleFragments
        ) { lines in
          var exclude = model.state.exclude
          exclude.titleFragments = lines
          model.setExclude(exclude)
        }
      }
      Section("Capture test") {
        Toggle(
          "Also run text recognition every minute",
          isOn: Binding(
            get: { model.state.recognizeTextEveryMinute },
            set: { model.setRecognizeTextEveryMinute($0) }))
        Text(
          "Stores recognized text next to the Accessibility text, so milestone 2 can compare them. Needs Screen Recording. Screenshots are never written to disk."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Section("Data") {
        Text(model.storage.folder.path).font(.caption.monospaced()).textSelection(.enabled)
        Button("Delete all data…", role: .destructive) { confirmDelete = true }
      }
    }
    .formStyle(.grouped)
    .confirmationDialog(
      "Delete all data?", isPresented: $confirmDelete
    ) {
      Button("Delete everything", role: .destructive) { model.deleteAllData() }
    } message: {
      Text(
        "This deletes the ledger, the capture log, and your allocations. It cannot be undone.")
    }
  }
}

private struct AllocationEditor: View {
  @State var allocation: Allocation
  let save: (Allocation) -> Void
  let remove: (Allocation) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        TextField("Name", text: $allocation.name).font(.headline)
        Button(role: .destructive) {
          remove(allocation)
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
      }
      TextField(
        "Description the model reads", text: $allocation.descriptionText, axis: .vertical
      )
      .lineLimit(1...3)
      HStack {
        Stepper(value: hours, in: 0...168) {
          Text("\(hours.wrappedValue) h")
        }
        Stepper(value: minutes, in: 0...55, step: 5) {
          Text("\(minutes.wrappedValue) min")
        }
        Picker("per", selection: $allocation.period) {
          Text("day").tag(BudgetPeriod.day)
          Text("week").tag(BudgetPeriod.week)
        }
        .fixedSize()
      }
    }
    .padding(.vertical, 4)
    .onChange(of: allocation) { _, new in save(new) }
  }

  private var hours: Binding<Int> {
    Binding(
      get: { allocation.budgetMinutes / 60 },
      set: { allocation.budgetMinutes = $0 * 60 + allocation.budgetMinutes % 60 })
  }

  private var minutes: Binding<Int> {
    Binding(
      get: { allocation.budgetMinutes % 60 },
      set: { allocation.budgetMinutes = allocation.budgetMinutes / 60 * 60 + $0 })
  }
}

/// A text box with one entry per line. Saves when the text changes.
private struct ListEditor: View {
  let title: String
  let lines: [String]
  @State private var text: String
  let save: ([String]) -> Void

  init(title: String, lines: [String], save: @escaping ([String]) -> Void) {
    self.title = title
    self.lines = lines
    self._text = State(initialValue: lines.joined(separator: "\n"))
    self.save = save
  }

  static func parse(_ text: String) -> [String] {
    text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  var body: some View {
    VStack(alignment: .leading) {
      Text(title).font(.caption)
      TextEditor(text: $text)
        .font(.body.monospaced())
        .frame(minHeight: 60, maxHeight: 120)
        .onChange(of: text) { _, new in
          if Self.parse(new) != lines { save(Self.parse(new)) }
        }
        // Reload when the model changes from elsewhere, such as "Delete all data".
        .onChange(of: lines) { _, new in
          if Self.parse(text) != new { text = new.joined(separator: "\n") }
        }
    }
  }
}
