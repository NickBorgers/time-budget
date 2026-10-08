import Foundation

/// How often an allocation's budget starts over.
public enum BudgetPeriod: String, Codable, Sendable {
  case day
  case week
}

/// A named kind of work with a time budget (spec F1).
public struct Allocation: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  /// What the classifier reads to decide whether a slice of work belongs here.
  public var descriptionText: String
  public var budgetMinutes: Int
  public var period: BudgetPeriod

  public init(
    id: UUID = UUID(),
    name: String,
    descriptionText: String,
    budgetMinutes: Int,
    period: BudgetPeriod
  ) {
    self.id = id
    self.name = name
    self.descriptionText = descriptionText
    self.budgetMinutes = budgetMinutes
    self.period = period
  }

  /// The four starting allocations the app suggests, for a 40-hour week.
  public static var starterSet: [Allocation] {
    [
      Allocation(
        name: "Focus work",
        descriptionText:
          "Planned work on my own projects, with no request from another person",
        budgetMinutes: 20 * 60, period: .week),
      Allocation(
        name: "Partner team help",
        descriptionText: "Work that answers a request from a person outside my team",
        budgetMinutes: 8 * 60, period: .week),
      Allocation(
        name: "Interrupts",
        descriptionText: "Unplanned requests that I answer in less than 15 minutes",
        budgetMinutes: 6 * 60, period: .week),
      Allocation(
        name: "Developing talent",
        descriptionText: "Coaching, reviews, and feedback for people on my team",
        budgetMinutes: 6 * 60, period: .week),
    ]
  }
}
