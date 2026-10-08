import Foundation
import Testing

@testable import TimeBudgetCore

@Suite("BudgetStatus")
struct BudgetStatusTests {
  @Test func remainingNeverGoesBelowZero() {
    #expect(BudgetStatus(usedMinutes: 90, budgetMinutes: 60).remainingMinutes == 0)
    #expect(BudgetStatus(usedMinutes: 15, budgetMinutes: 60).remainingMinutes == 45)
  }

  @Test func warningFiresAtEightyPercent() {
    let before = BudgetStatus(usedMinutes: 47, budgetMinutes: 60)
    let after = BudgetStatus(usedMinutes: 48, budgetMinutes: 60)
    #expect(after.newlyReached(since: before) == [.warning])
  }

  @Test func spentFiresAtTheBudget() {
    let before = BudgetStatus(usedMinutes: 59, budgetMinutes: 60)
    let after = BudgetStatus(usedMinutes: 60, budgetMinutes: 60)
    #expect(after.newlyReached(since: before) == [.spent])
  }

  @Test func aJumpAcrossBothReportsBothInOrder() {
    let before = BudgetStatus(usedMinutes: 10, budgetMinutes: 60)
    let after = BudgetStatus(usedMinutes: 70, budgetMinutes: 60)
    #expect(after.newlyReached(since: before) == [.warning, .spent])
  }

  @Test func nothingNewMeansNothingReported() {
    let status = BudgetStatus(usedMinutes: 70, budgetMinutes: 60)
    #expect(status.newlyReached(since: status).isEmpty)
  }

  @Test func aCorrectionThatLowersUsageReportsNothing() {
    let before = BudgetStatus(usedMinutes: 70, budgetMinutes: 60)
    let after = BudgetStatus(usedMinutes: 30, budgetMinutes: 60)
    #expect(after.newlyReached(since: before).isEmpty)
  }

  @Test func aZeroBudgetIsSpentFromTheStart() {
    #expect(BudgetStatus(usedMinutes: 0, budgetMinutes: 0).hasReached(.spent))
  }
}

@Suite("Allocation")
struct AllocationTests {
  @Test func starterSetMatchesTheSpecTable() {
    let set = Allocation.starterSet
    #expect(
      set.map(\.name) == ["Focus work", "Partner team help", "Interrupts", "Developing talent"])
    #expect(set.map(\.budgetMinutes) == [1200, 480, 360, 360])
    #expect(set.allSatisfy { $0.period == .week })
    #expect(set.reduce(0) { $0 + $1.budgetMinutes } == 40 * 60)
  }

  @Test func roundTripsThroughJSON() throws {
    let original = Allocation.starterSet[0]
    let data = try JSONEncoder().encode(original)
    #expect(try JSONDecoder().decode(Allocation.self, from: data) == original)
  }
}
