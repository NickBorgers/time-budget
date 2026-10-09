import Foundation
import TimeBudgetCore
import UserNotifications

/// Budget alerts through macOS notifications (spec F5).
final class Notifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  private var center: UNUserNotificationCenter { .current() }

  func start() {
    center.delegate = self
    center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  func isAllowed() async -> Bool {
    let settings = await center.notificationSettings()
    return settings.authorizationStatus == .authorized
      || settings.authorizationStatus == .provisional
  }

  /// Returns true when macOS accepted the alert for delivery.
  func announce(
    _ threshold: BudgetThreshold, for allocation: Allocation, status: BudgetStatus,
    key: PeriodKey
  ) async -> Bool {
    guard await isAllowed() else { return false }
    let content = UNMutableNotificationContent()
    content.title = AlertText.title(for: allocation, threshold: threshold)
    content.body = AlertText.body(for: allocation, status: status, threshold: threshold)
    // 80% is a quiet notification. 100% makes a sound.
    if threshold == .spent { content.sound = .default }
    let id =
      "\(key.allocationID.uuidString)-\(key.period.rawValue)-\(Int(key.periodStart.timeIntervalSince1970))-\(threshold.rawValue)"
    do {
      try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
      return true
    } catch {
      return false
    }
  }

  /// Show alerts even while the menu bar panel is open.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound, .list]
  }
}
