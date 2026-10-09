import Foundation

/// File names and retention for the capture log: one JSON Lines file per day.
public enum SliceLog {
  /// Spec "What the app stores": slice evidence is kept for 14 days.
  public static let keepDays = 14

  public static func fileName(for date: Date, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    return "slices-\(day).jsonl"
  }

  /// The files among `names` that hold any record `keepDays` days old or older
  /// at `now`. A whole day is deleted at once, so no record lives longer than
  /// `keepDays` days.
  /// Names that do not look like log files are never listed.
  public static func expired(
    _ names: [String], now: Date, calendar: Calendar, keepDays: Int = keepDays
  ) -> [String] {
    guard
      let cutoff = calendar.date(
        byAdding: .day, value: -keepDays, to: calendar.startOfDay(for: now))
    else { return [] }
    let last = fileName(for: cutoff, calendar: calendar)
    // The names sort by date because the date is zero-padded year-month-day.
    return names.filter { isLogFile($0) && $0 <= last }
  }

  static func isLogFile(_ name: String) -> Bool {
    name.wholeMatch(of: /slices-\d{4}-\d{2}-\d{2}\.jsonl/) != nil
  }

  /// One line of JSON, with a newline at the end.
  public static func line(for record: SliceRecord) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(record)
    data.append(0x0A)
    return data
  }
}

/// The words of a budget alert (spec "During the day").
public enum AlertText {
  public static func title(for allocation: Allocation, threshold: BudgetThreshold) -> String {
    switch threshold {
    case .warning: "\(allocation.name) is at 80%"
    case .spent: "\(allocation.name) is spent for \(allocation.period.phrase)."
    }
  }

  public static func body(
    for allocation: Allocation, status: BudgetStatus, threshold: BudgetThreshold
  )
    -> String
  {
    switch threshold {
    case .warning:
      "\(TextTools.duration(minutes: status.remainingMinutes)) left of \(TextTools.duration(minutes: status.budgetMinutes)) \(allocation.period.phrase)."
    case .spent:
      "You used \(TextTools.duration(minutes: status.usedMinutes)) of \(TextTools.duration(minutes: status.budgetMinutes))."
    }
  }
}
