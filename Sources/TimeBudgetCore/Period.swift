import Foundation

extension BudgetPeriod {
  /// The start of the period that contains `date` (spec F4: the ledger resets
  /// at the start of each period). A week starts on the calendar's first weekday.
  public func start(containing date: Date, calendar: Calendar) -> Date {
    let component: Calendar.Component = self == .day ? .day : .weekOfYear
    // dateInterval(of:for:) only fails for components a calendar does not
    // have. Day and week exist in every calendar, so the fallback is unused.
    return calendar.dateInterval(of: component, for: date)?.start
      ?? calendar.startOfDay(for: date)
  }

  /// Words for an alert: "today" or "this week".
  public var phrase: String {
    switch self {
    case .day: "today"
    case .week: "this week"
    }
  }
}
