import SwiftUI
import TimeBudgetCore

/// Scaffold only: proves the app target builds, links TimeBudgetCore, and runs
/// as a menu bar item. Capture, classification, and the ledger are later work.
@main
struct TimeBudgetApp: App {
  var body: some Scene {
    MenuBarExtra("Time Budget") {
      Text("Time Budget")
      Divider()
      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
    }
  }
}
