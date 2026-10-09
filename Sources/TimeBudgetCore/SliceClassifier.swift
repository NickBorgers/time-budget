import Foundation

/// How a slice got its label.
public enum DecisionMethod: Codable, Equatable, Sendable {
  /// Step 2: no input for too long.
  case idle
  /// Step 3: the evidence matched the previous slice, so its label was copied.
  case unchanged
  /// Step 4: the pinned rule with this identifier matched.
  case rule(UUID)
  /// Steps 5 and 6: the model scored the options.
  case model
  /// No model decision: there was no model, no allocation, or the model run failed.
  case noModel
}

/// One option and the probability that the model gave it.
public struct OptionScore: Codable, Equatable, Sendable {
  public var name: String
  public var label: SliceLabel
  public var probability: Double

  public init(name: String, label: SliceLabel, probability: Double) {
    self.name = name
    self.label = label
    self.probability = probability
  }
}

/// The classifier's label for one slice, with the evidence for the reason line
/// (spec "What the user sees as the reason").
public struct SliceDecision: Codable, Equatable, Sendable {
  public var label: SliceLabel
  public var method: DecisionMethod
  /// The probability of the winning option, from 0 to 1. A pinned rule is
  /// certain. Nil for idle and for no model decision.
  public var confidence: Double?
  /// Every option the model scored, in the order of the request. Only for
  /// `.model`.
  public var options: [OptionScore]?

  public init(
    label: SliceLabel, method: DecisionMethod, confidence: Double? = nil,
    options: [OptionScore]? = nil
  ) {
    precondition(confidence.map { (0...1).contains($0) } ?? true, "confidence is a probability")
    self.label = label
    self.method = method
    self.confidence = confidence
    self.options = options
  }
}

/// The last slice that got a label, for step 3.
public struct PreviousSlice: Equatable, Sendable {
  public var evidence: SliceEvidence
  public var decision: SliceDecision

  public init(evidence: SliceEvidence, decision: SliceDecision) {
    self.evidence = evidence
    self.decision = decision
  }
}

/// What the model must score for one slice.
public struct ModelRequest: Equatable, Sendable {
  public var premise: String
  public var options: [ModelOption]

  /// One model input for each option, in the order of `options`.
  public var inputs: [String] {
    options.map { ClassifierPrompt.input(premise: premise, hypothesis: $0.hypothesis) }
  }
}

/// The classification steps of the spec, without the model run itself.
///
/// The model needs MLX, which exists only on the Mac, and it takes seconds.
/// So the app calls `start`, runs the model on the request when there is one,
/// and calls `finish` with the scores. Every choice is made here, where it is
/// tested, and the model never decides more than the scores.
public struct SliceClassifier: Sendable {
  public var rules: SliceRules
  public var allocations: [Allocation]
  public var pinnedRules: [PinnedRule]
  /// Step 6: below this probability, the slice is `Unassigned`. The value is
  /// proposed in the spec, and the two-week trial (milestone 6) adjusts it.
  public var threshold: Double

  public init(
    rules: SliceRules, allocations: [Allocation], pinnedRules: [PinnedRule],
    threshold: Double = 0.6
  ) {
    precondition((0...1).contains(threshold))
    self.rules = rules
    self.allocations = allocations
    self.pinnedRules = pinnedRules
    self.threshold = threshold
  }

  public enum Step: Equatable, Sendable {
    /// Step 1: an excluded window. Store nothing.
    case drop
    case decided(SliceDecision)
    case askModel(ModelRequest)
  }

  /// Steps 1 to 4, and the request for step 5.
  ///
  /// `previous` is the last slice with a label. Step 3 copies its label only
  /// when the evidence is the same, the label came from a rule or the model,
  /// and the label still exists.
  public func start(_ evidence: SliceEvidence, previous: PreviousSlice?) -> Step {
    guard let label = rules.label(for: evidence, selected: .unassigned) else { return .drop }
    if label == .idle { return .decided(SliceDecision(label: .idle, method: .idle)) }

    if let previous, previous.evidence.sameContent(as: evidence), isCopyable(previous.decision) {
      return .decided(
        SliceDecision(
          label: previous.decision.label, method: .unchanged,
          confidence: previous.decision.confidence))
    }

    let known = Set(allocations.map(\.id))
    if let rule = pinnedRules.first(where: {
      known.contains($0.allocationID) && $0.matches(evidence)
    }) {
      return .decided(
        SliceDecision(label: .allocation(rule.allocationID), method: .rule(rule.id), confidence: 1))
    }

    guard !allocations.isEmpty else {
      return .decided(SliceDecision(label: .unassigned, method: .noModel))
    }
    return .askModel(
      ModelRequest(
        premise: ClassifierPrompt.premise(for: evidence),
        options: ClassifierPrompt.options(for: allocations)))
  }

  /// Steps 5 and 6. `probabilities` holds one value for each option of
  /// `request`, from `Decision.optionProbabilities`. Nil means that the model
  /// did not run or failed.
  ///
  /// When `None of these` wins, the slice is `Unassigned`: it belongs to no
  /// allocation, so it adds no time.
  public func finish(_ request: ModelRequest, probabilities: [Double]?) -> SliceDecision {
    guard let probabilities, probabilities.count == request.options.count,
      probabilities.allSatisfy({ $0.isFinite && (0...1).contains($0) })
    else {
      return SliceDecision(label: .unassigned, method: .noModel)
    }
    let scores = zip(request.options, probabilities).map {
      OptionScore(name: $0.name, label: $0.label, probability: $1)
    }
    // The first of equal scores wins, so the result does not depend on chance.
    var best = scores[0]
    for score in scores.dropFirst() where score.probability > best.probability { best = score }
    let label = best.probability >= threshold ? best.label : .unassigned
    return SliceDecision(
      label: label, method: .model, confidence: best.probability, options: scores)
  }

  private func isCopyable(_ decision: SliceDecision) -> Bool {
    switch decision.method {
    case .idle, .noModel: return false
    case .unchanged, .rule, .model: break
    }
    switch decision.label {
    case .allocation(let id): return allocations.contains { $0.id == id }
    case .unassigned: return true
    case .idle: return false
    }
  }
}
