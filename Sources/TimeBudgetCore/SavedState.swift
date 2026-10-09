import Foundation

/// Everything the app keeps through a restart, except the capture log.
public struct SavedState: Codable, Equatable, Sendable {
  public var allocations: [Allocation]
  public var ledger: Ledger
  /// The allocation the user says they are working on. Nil means `Unassigned`.
  public var selectedAllocationID: UUID?
  public var exclude: ExcludeList
  /// Run text recognition every minute, next to the Accessibility text, for
  /// the capture test (milestone 2).
  public var recognizeTextEveryMinute: Bool
  /// Capture is paused until this time. `Date.distantFuture` means until the
  /// user starts it again (spec F8).
  public var pausedUntil: Date?

  public init(
    allocations: [Allocation] = Allocation.starterSet,
    ledger: Ledger = Ledger(),
    selectedAllocationID: UUID? = nil,
    exclude: ExcludeList = .defaults,
    recognizeTextEveryMinute: Bool = true,
    pausedUntil: Date? = nil
  ) {
    self.allocations = allocations
    self.ledger = ledger
    self.selectedAllocationID = selectedAllocationID
    self.exclude = exclude
    self.recognizeTextEveryMinute = recognizeTextEveryMinute
    self.pausedUntil = pausedUntil
  }

  public var selectedAllocation: Allocation? {
    allocations.first { $0.id == selectedAllocationID }
  }

  /// The user's label for the current minute.
  public var selectedLabel: SliceLabel {
    selectedAllocation.map { .allocation($0.id) } ?? .unassigned
  }

  public func isPaused(at date: Date) -> Bool {
    pausedUntil.map { date < $0 } ?? false
  }
}
