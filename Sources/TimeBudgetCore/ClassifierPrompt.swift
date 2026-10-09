import Foundation

/// One answer that the model scores: an allocation, or `None of these`.
public struct ModelOption: Equatable, Sendable {
  /// The label that the slice gets when this option wins.
  public var label: SliceLabel
  public var name: String
  public var hypothesis: String

  public init(label: SliceLabel, name: String, hypothesis: String) {
    self.label = label
    self.name = name
    self.hypothesis = hypothesis
  }
}

/// The text that the model reads (spec "Classification design", step 5).
///
/// The premise is the screen evidence. Each option is one hypothesis, written
/// with the template of `openjev_decide.py` on the model card, so the model
/// sees the same shape of input that it was trained and tested on.
///
/// The premise holds text from the screen, which is not trusted. Hostile text
/// can change the scores. It cannot start an action: the model only scores,
/// and the rules and alerts run outside it.
public enum ClassifierPrompt {
  /// `config.nli_template` of the checkpoint.
  public static let template = "Premise: {premise}\nHypothesis: {hypothesis}"
  public static let question = "Which type of work does the person do on this screen?"
  public static let noneName = "None of these"
  public static let noneRubric =
    "The screen shows personal activity, or work that is not one of my listed types of work."

  /// The evidence as plain lines. Empty fields are left out.
  public static func premise(for evidence: SliceEvidence) -> String {
    var lines = ["App: \(evidence.appName)"]
    if let title = evidence.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
      !title.isEmpty
    {
      lines.append("Window title: \(title)")
    }
    if let host = evidence.host, !host.isEmpty { lines.append("Website: \(host)") }
    let text = [evidence.visibleText, evidence.recognizedText ?? ""]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
    if let text {
      lines.append("Text on the screen:\n\(text)")
    } else {
      lines.append("Text on the screen: none")
    }
    let typed = evidence.typedText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !typed.isEmpty { lines.append("Typed in the last minute:\n\(typed)") }
    return lines.joined(separator: "\n")
  }

  /// The hypothesis for one allocation. Its description is the rubric. With no
  /// description, the name is the rubric, as in `openjev_decide.py`.
  public static func hypothesis(for allocation: Allocation) -> String {
    let rubric = allocation.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
    return hypothesis(name: allocation.name, rubric: rubric.isEmpty ? allocation.name : rubric)
  }

  static func hypothesis(name: String, rubric: String) -> String {
    "The answer to \"\(question)\" is \(name): \(rubric)"
  }

  /// Each allocation, then `None of these`. The order does not change the
  /// scores: each option is scored on its own.
  public static func options(for allocations: [Allocation]) -> [ModelOption] {
    allocations.map {
      ModelOption(label: .allocation($0.id), name: $0.name, hypothesis: hypothesis(for: $0))
    }
      + [
        ModelOption(
          label: .unassigned, name: noneName,
          hypothesis: hypothesis(name: noneName, rubric: noneRubric))
      ]
  }

  /// One model input. Both parts are trimmed, as on the model card.
  public static func input(premise: String, hypothesis: String) -> String {
    template
      .replacingOccurrences(
        of: "{premise}", with: premise.trimmingCharacters(in: .whitespacesAndNewlines)
      )
      .replacingOccurrences(
        of: "{hypothesis}", with: hypothesis.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}
