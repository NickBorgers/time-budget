import AppKit
import SwiftUI

/// The main window: the same panel as the menu bar item. It opens at launch
/// and each time the user opens the app again or clicks its Dock icon, because
/// a full menu bar or the camera notch can hide the menu bar item.
@MainActor
enum MainWindow {
  private static var window: NSWindow?
  private static weak var model: AppModel?
  static var currentModel: AppModel? { model }

  static func show(model: AppModel) {
    self.model = model
    show()
  }

  static func show() {
    guard let model else { return }
    if window == nil {
      let window = NSWindow(
        contentViewController: NSHostingController(rootView: MenuPanel(model: model)))
      window.title = "Time Budget"
      window.styleMask = [.titled, .closable, .miniaturizable]
      // Closing hides the window. Reopening the app shows it again.
      window.isReleasedWhenClosed = false
      window.center()
      self.window = window
    }
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

/// The settings window: allocations, exclusions, capture options. AppKit for
/// the same reason as the main window: SwiftUI opens its Settings scene only
/// from SettingsLink inside a SwiftUI scene, and ignores the old menu action.
@MainActor
enum SettingsWindowController {
  private static var window: NSWindow?

  static func show() {
    guard let model = MainWindow.currentModel else { return }
    if window == nil {
      let window = NSWindow(
        contentViewController: NSHostingController(rootView: SettingsWindow(model: model)))
      window.title = "Time Budget Settings"
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
      window.isReleasedWhenClosed = false
      window.setContentSize(NSSize(width: 600, height: 520))
      window.center()
      self.window = window
    }
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

/// Shows the main window when the user clicks the Dock icon or opens the app
/// while it already runs.
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    MainActor.assumeIsolated { MainWindow.show() }
    return true
  }
}
