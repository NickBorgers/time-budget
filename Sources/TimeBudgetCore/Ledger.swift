import Foundation

/// One allocation in one budget period. The period kind is part of the key: a
/// day and a week can start at the same moment, and an allocation can change
/// from one to the other.
public struct PeriodKey: Hashable, Codable, Sendable {
  public let allocationID: UUID
  public let period: BudgetPeriod
  public let periodStart: Date

  public init(allocationID: UUID, period: BudgetPeriod, periodStart: Date) {
    self.allocationID = allocationID
    self.period = period
    self.periodStart = periodStart
  }
}

/// Minutes of work for each allocation in each period (spec F4), and the alert
/// thresholds already announced in each period (spec F5).
///
/// Old periods stay in the ledger: they are the long-term record. A new period
/// starts at zero because lookups use the key of the current period.
public struct Ledger: Codable, Equatable, Sendable {
  public private(set) var minutes: [PeriodKey: Int] = [:]
  public private(set) var announced: [PeriodKey: Set<BudgetThreshold>] = [:]

  public init() {}

  public func key(for allocation: Allocation, at date: Date, calendar: Calendar) -> PeriodKey {
    PeriodKey(
      allocationID: allocation.id, period: allocation.period,
      periodStart: allocation.period.start(containing: date, calendar: calendar))
  }

  public func usedMinutes(for allocation: Allocation, at date: Date, calendar: Calendar) -> Int {
    minutes[key(for: allocation, at: date, calendar: calendar)] ?? 0
  }

  public func status(for allocation: Allocation, at date: Date, calendar: Calendar)
    -> BudgetStatus
  {
    BudgetStatus(
      usedMinutes: usedMinutes(for: allocation, at: date, calendar: calendar),
      budgetMinutes: allocation.budgetMinutes)
  }

  /// Adds `count` minutes of work at `date` to `allocation`. Returns the
  /// thresholds to announce now: each one only once in each period.
  @discardableResult
  public mutating func add(
    minutes count: Int = 1, to allocation: Allocation, at date: Date, calendar: Calendar
  ) -> [BudgetThreshold] {
    precondition(count >= 0, "use a correction to remove minutes")
    let key = key(for: allocation, at: date, calendar: calendar)
    minutes[key, default: 0] += count
    let status = BudgetStatus(usedMinutes: minutes[key]!, budgetMinutes: allocation.budgetMinutes)
    let done = announced[key, default: []]
    // Compare with "already announced", not with the previous total. A budget
    // that the user lowers below the used time then fires once, on the next minute.
    let fresh = BudgetThreshold.allCases.filter { status.hasReached($0) && !done.contains($0) }
    if !fresh.isEmpty { announced[key] = done.union(fresh) }
    return fresh
  }

  /// Marks `threshold` as not announced, so the next minute announces it
  /// again. Use it when the alert did not reach the user.
  public mutating func withdraw(_ threshold: BudgetThreshold, for key: PeriodKey) {
    announced[key]?.remove(threshold)
  }
}

extension BudgetThreshold: Codable {}
