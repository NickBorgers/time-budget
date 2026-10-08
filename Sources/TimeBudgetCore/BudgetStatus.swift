/// A point on a budget where the app speaks up (spec F5).
public enum BudgetThreshold: Int, CaseIterable, Comparable, Sendable {
  /// 80% of the budget: one quiet notification.
  case warning = 80
  /// 100% of the budget: an alert with a decline message.
  case spent = 100

  public static func < (lhs: BudgetThreshold, rhs: BudgetThreshold) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// Time used against a budget, in whole minutes.
public struct BudgetStatus: Equatable, Sendable {
  public let usedMinutes: Int
  public let budgetMinutes: Int

  public init(usedMinutes: Int, budgetMinutes: Int) {
    self.usedMinutes = usedMinutes
    self.budgetMinutes = budgetMinutes
  }

  public var remainingMinutes: Int { max(0, budgetMinutes - usedMinutes) }

  /// Whether `threshold` has been reached. A zero budget is spent from the start.
  public func hasReached(_ threshold: BudgetThreshold) -> Bool {
    usedMinutes * 100 >= budgetMinutes * threshold.rawValue
  }

  /// The thresholds this status has reached that `previous` had not, lowest first.
  ///
  /// The caller keeps the set of thresholds already announced in the current
  /// period, so each one fires once. This function only reports the crossing.
  public func newlyReached(since previous: BudgetStatus) -> [BudgetThreshold] {
    BudgetThreshold.allCases.filter { hasReached($0) && !previous.hasReached($0) }
  }
}
