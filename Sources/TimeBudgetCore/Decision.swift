import Foundation

/// The math of a typed decision with the OpenJev cross-encoder (spec "Model").
///
/// The model reads one premise and one hypothesis, and returns three logits in
/// the order contradiction, entailment, neutral. A decision scores each option
/// as its own hypothesis over the same premise. This file turns those logits
/// into one probability for each option, the same way as `openjev_decide.py`
/// on the model card: a softmax over each row, the entailment column, then a
/// normalization over the options.
public enum Decision {
  /// The column of the entailment logit in the model's output.
  public static let entailmentIndex = 1
  public static let labelCount = 3

  /// One probability for each row of `logits`, adding up to 1. Nil when a row
  /// has the wrong length or a value that is not finite, or when no option has
  /// any entailment at all: there is then no distribution to report.
  public static func optionProbabilities(logits: [[Double]]) -> [Double]? {
    guard !logits.isEmpty else { return nil }
    var entailment: [Double] = []
    for row in logits {
      guard row.count == labelCount, row.allSatisfy(\.isFinite) else { return nil }
      // Subtract the largest logit, so exp() cannot overflow.
      let top = row.max()!
      let exps = row.map { exp($0 - top) }
      entailment.append(exps[entailmentIndex] / exps.reduce(0, +))
    }
    let total = entailment.reduce(0, +)
    guard total > 0, total.isFinite else { return nil }
    return entailment.map { $0 / total }
  }
}

/// The spec's shared-prefix method: the long premise is the same for every
/// option, so the model reads it once, and then reads only the part of each
/// input that differs.
public enum TokenPrefix {
  /// The number of leading tokens that every sequence shares. At least one
  /// token of each sequence stays outside the prefix, because the score reads
  /// the hidden state of the last token, and each sequence needs its own.
  public static func sharedLength(_ sequences: [[Int]]) -> Int {
    guard let shortest = sequences.map(\.count).min(), shortest > 0 else { return 0 }
    let first = sequences[0]
    var length = 0
    while length < shortest - 1,
      sequences.allSatisfy({ $0[length] == first[length] })
    {
      length += 1
    }
    return length
  }
}
