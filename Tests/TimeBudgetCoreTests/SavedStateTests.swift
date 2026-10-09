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

  @Test func readsAStateFromBeforeTheClassifier() throws {
    // The hello-world build saved no rules and no label source.
    let old = SavedState(pausedUntil: date(8))
    var json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
    json["pinnedRules"] = nil
    json["labelSource"] = nil
    let data = try JSONSerialization.data(withJSONObject: json)
    let state = try JSONDecoder().decode(SavedState.self, from: data)
    #expect(state.pinnedRules.isEmpty)
    #expect(state.labelSource == .model)
    #expect(state.allocations == old.allocations)
    #expect(state.pausedUntil == old.pausedUntil)
  }

  @Test func roundTripsRulesAndLabelSource() throws {
    var state = SavedState()
    state.labelSource = .user
    state.pinnedRules = [
      PinnedRule(
        field: .host, match: .equals, text: "github.com", allocationID: state.allocations[0].id)
    ]
    let data = try JSONEncoder().encode(state)
    #expect(try JSONDecoder().decode(SavedState.self, from: data) == state)
  }

  @Test func theUserLabelCountsWhenAskedOrWhenThereIsNoModel() {
    var state = SavedState()
    #expect(state.labelSource == .model)
    #expect(state.countsModelLabel(modelReady: true))
    #expect(!state.countsModelLabel(modelReady: false))
    state.labelSource = .user
    #expect(!state.countsModelLabel(modelReady: true))
  }
}
