import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXNN
import TimeBudgetCore
import Tokenizers

public enum JevModelError: LocalizedError {
  case missingFile(String)
  case badHead(String)
  case emptyInput

  public var errorDescription: String? {
    switch self {
    case .missingFile(let name): "The model folder has no \(name)."
    case .badHead(let detail): "The score head is not usable: \(detail)"
    case .emptyInput: "A model input has no tokens."
    }
  }
}

/// The OpenJev cross-encoder on MLX, inside the app process (spec "Runtime").
///
/// The folder comes from `scripts/convert_openjev.py`: a Qwen3.5 text model
/// that mlx-swift-lm loads, and a separate `score.safetensors` head with three
/// outputs: contradiction, entailment, neutral.
///
/// The app opens no port and makes no network request here. The tokenizer and
/// the weights are read from the folder.
///
/// An actor, so the seconds of model work run off the main thread, one request
/// at a time.
public actor JevModel {
  private let model: Qwen35Model
  private let tokenizer: any Tokenizers.Tokenizer
  /// The checkpoint name from `SOURCE.json`, for the panel and the log.
  public nonisolated let name: String

  public init(folder: URL) async throws {
    for file in ["config.json", "score.safetensors", "tokenizer.json"] {
      guard FileManager.default.fileExists(atPath: folder.appendingPathComponent(file).path)
      else { throw JevModelError.missingFile(file) }
    }
    let configData = try Data(contentsOf: folder.appendingPathComponent("config.json"))
    let config = try JSONDecoder().decode(Qwen35Configuration.self, from: configData)
    let base = try JSONDecoder().decode(BaseConfiguration.self, from: configData)
    let model = Qwen35Model(config)
    try await loadWeights(
      modelDirectory: folder, model: model, perLayerQuantization: base.perLayerQuantization)

    // The checkpoint ties the language-model head to the embedding, and this
    // use needs no word logits. The score head takes the place of `lm_head`,
    // so one forward pass returns the three label logits at each position.
    let head = try loadArrays(url: folder.appendingPathComponent("score.safetensors"))
    guard let weight = head["weight"], weight.ndim == 2, weight.dim(0) == Decision.labelCount
    else { throw JevModelError.badHead("expected a weight of shape [3, hidden]") }
    let score = Linear(weight.dim(1), Decision.labelCount, bias: false)
    try score.update(parameters: ModuleParameters.unflattened(["weight": weight]), verify: [.all])
    try model.update(
      modules: ModuleChildren.unflattened(["language_model.lm_head": score]), verify: [.all])
    try model.prepare()
    eval(model)

    self.model = model
    self.tokenizer = try await AutoTokenizer.from(modelFolder: folder)
    self.name =
      (try? JSONDecoder().decode(
        Source.self, from: Data(contentsOf: folder.appendingPathComponent("SOURCE.json"))))?
      .checkpoint ?? folder.lastPathComponent
  }

  private struct Source: Decodable { var checkpoint: String }

  /// The token ids of each input, as the model reads them.
  public func tokens(for inputs: [String]) -> [[Int]] {
    inputs.map { tokenizer.encode(text: $0, addSpecialTokens: true) }
  }

  /// The three logits for each input, in order.
  ///
  /// The inputs of one request share the premise. The shared tokens run once,
  /// and each input continues from a copy of that state (the spec's
  /// shared-prefix method). The result is the same as one full pass for each
  /// input.
  public func logits(for inputs: [String]) throws -> [[Double]] {
    let sequences = tokens(for: inputs)
    guard sequences.allSatisfy({ !$0.isEmpty }) else { throw JevModelError.emptyInput }
    let shared = TokenPrefix.sharedLength(sequences)

    var prefix: [KVCache]?
    if shared > 0 {
      let cache = try model.newCache(parameters: nil)
      let out = model(Self.array(sequences[0][..<shared]), cache: cache)
      eval([out] + cache.flatMap { $0.innerState() })
      prefix = cache
    }

    var result: [[Double]] = []
    for sequence in sequences {
      let cache = try prefix.map { $0.map { $0.copy() } } ?? model.newCache(parameters: nil)
      let out = model(Self.array(sequence[shared...]), cache: cache)
      let last = out[0, -1].asType(.float32)
      eval(last)
      result.append(last.asArray(Float.self).map(Double.init))
    }
    Memory.clearCache()
    return result
  }

  private static func array(_ tokens: ArraySlice<Int>) -> MLXArray {
    MLXArray(tokens.map { Int32($0) }).reshaped(1, tokens.count)
  }

  /// One probability for each input, or nil when the logits give none.
  public func probabilities(for inputs: [String]) throws -> [Double]? {
    Decision.optionProbabilities(logits: try logits(for: inputs))
  }
}
