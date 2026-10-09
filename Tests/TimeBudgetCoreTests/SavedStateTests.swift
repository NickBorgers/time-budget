import Foundation
import Testing

@testable import TimeBudgetCore

@Suite("SavedState")
struct SavedStateTests {
  @Test func noSelectionIsUnassigned() {
    #expect(SavedState().selectedLabel == .unassigned)
  }

  @Test func aSelectionThatNoLongerExistsIsUnassigned() {
    #expect(SavedState(selectedAllocationID: UUID()).selectedLabel == .unassigned)
  }

  @Test func aSelectionIsItsAllocation() {
    var state = SavedState()
    let focus = state.allocations[0]
    state.selectedAllocationID = focus.id
    #expect(state.selectedLabel == .allocation(focus.id))
  }

  @Test func pauseEndsAtItsTime() {
    let state = SavedState(pausedUntil: date(8, 12))
    #expect(state.isPaused(at: date(8, 11, 59)))
    #expect(!state.isPaused(at: date(8, 12)))
    #expect(SavedState(pausedUntil: .distantFuture).isPaused(at: date(30)))
    #expect(!SavedState().isPaused(at: date(8)))
  }

  @Test func roundTripsThroughJSON() throws {
    var state = SavedState(pausedUntil: .distantFuture)
    state.selectedAllocationID = state.allocations[1].id
    state.ledger.add(minutes: 5, to: state.allocations[1], at: date(8), calendar: testCalendar)
    let data = try JSONEncoder().encode(state)
    #expect(try JSONDecoder().decode(SavedState.self, from: data) == state)
  }
}
