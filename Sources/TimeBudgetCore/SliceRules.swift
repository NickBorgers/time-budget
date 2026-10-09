import Foundation

/// The fixed steps that run before any classifier (spec "Classification
/// design", steps 1 and 2). In this first version the user is the classifier:
/// the label is the allocation the user selected in the menu bar.
public struct SliceRules: Sendable {
  public var exclude: ExcludeList
  /// Spec step 2: no input for longer than this means `Idle`.
  public var idleAfterSeconds: Double

  public init(exclude: ExcludeList = .defaults, idleAfterSeconds: Double = 5 * 60) {
    precondition(idleAfterSeconds.isFinite && idleAfterSeconds >= 0)
    self.exclude = exclude
    self.idleAfterSeconds = idleAfterSeconds
  }

  /// The label for `evidence`, or nil to drop the slice and store nothing.
  ///
  /// The exclude check here is a second gate. The reader must check the app,
  /// then the title and host, before it reads any text (see `ExcludeList`).
  /// An idle time that is negative or not a finite number counts as idle:
  /// unknown is not active work.
  ///
  /// The spec does not apply the idle rule during a meeting. The app does not
  /// read the calendar yet, so a meeting with no input counts as `Idle`.
  public func label(for evidence: SliceEvidence, selected: SliceLabel) -> SliceLabel? {
    if exclude.excludes(evidence) { return nil }
    let idle = evidence.secondsSinceInput
    if !idle.isFinite || idle < 0 || idle > idleAfterSeconds { return .idle }
    return selected
  }
}
