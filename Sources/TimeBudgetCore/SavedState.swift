import Foundation

/// Which label adds time to the ledger.
public enum LabelSource: String, Codable, CaseIterable, Sendable {
  /// The classifier's label (spec F3). The user's selection is still stored
  /// next to it, so the two can be compared.
  case model
  /// The allocation that the user selected by hand, as in the hello-world build.
  case user
}

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
  /// Rules that the user wrote. They run before the model (spec step 4).
  public var pinnedRules: [PinnedRule]
  public var labelSource: LabelSource

  public init(
    allocations: [Allocation] = Allocation.starterSet,
    ledger: Ledger = Ledger(),
    selectedAllocationID: UUID? = nil,
    exclude: ExcludeList = .defaults,
    recognizeTextEveryMinute: Bool = true,
    pausedUntil: Date? = nil,
    pinnedRules: [PinnedRule] = [],
    labelSource: LabelSource = .model
  ) {
    self.allocations = allocations
    self.ledger = ledger
    self.selectedAllocationID = selectedAllocationID
    self.exclude = exclude
    self.recognizeTextEveryMinute = recognizeTextEveryMinute
    self.pausedUntil = pausedUntil
    self.pinnedRules = pinnedRules
    self.labelSource = labelSource
  }

  /// True when the classifier's label adds time. With no model ready, the
  /// user's selection counts, so the app still works without a model.
  public func countsModelLabel(modelReady: Bool) -> Bool {
    labelSource == .model && modelReady
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

extension SavedState {
  private enum CodingKeys: String, CodingKey {
    case allocations, ledger, selectedAllocationID, exclude, recognizeTextEveryMinute, pausedUntil
    case pinnedRules, labelSource
  }

  /// Fields added after the hello-world build get their defaults, so its
  /// saved state still loads.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      allocations: try c.decode([Allocation].self, forKey: .allocations),
      ledger: try c.decode(Ledger.self, forKey: .ledger),
      selectedAllocationID: try c.decodeIfPresent(UUID.self, forKey: .selectedAllocationID),
      exclude: try c.decode(ExcludeList.self, forKey: .exclude),
      recognizeTextEveryMinute: try c.decode(Bool.self, forKey: .recognizeTextEveryMinute),
      pausedUntil: try c.decodeIfPresent(Date.self, forKey: .pausedUntil),
      pinnedRules: try c.decodeIfPresent([PinnedRule].self, forKey: .pinnedRules) ?? [],
      labelSource: try c.decodeIfPresent(LabelSource.self, forKey: .labelSource) ?? .model)
  }
}
