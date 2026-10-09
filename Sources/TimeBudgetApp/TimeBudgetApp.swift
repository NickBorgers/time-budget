import SwiftUI
import TimeBudgetCore

/// The menu bar app. Run it as a bundle (`make run`): notifications and the
/// macOS permissions need a bundle identifier.
@main
struct TimeBudgetApp: App {
  // SwiftUI creates the App value once, so a plain constant holds the one
  // model. @Observable tracks it without @State.
  private let model: AppModel
  @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

  init() {
    let model = AppModel()
    self.model = model
    // Start capture at launch, not when the panel first opens.
    DispatchQueue.main.async { model.start() }
  }

  var body: some Scene {
    MenuBarExtra {
      MenuPanel(model: model)
    } label: {
      Label(model.menuBarTitle, systemImage: model.menuBarSymbol)
        .labelStyle(.titleAndIcon)
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsWindow(model: model)
    }
  }
}
