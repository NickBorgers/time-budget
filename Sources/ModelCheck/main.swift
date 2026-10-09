import Darwin
import Foundation
import MLX
import TimeBudgetCore
import TimeBudgetModel

// Milestone 1, the model test: run the classifier on a fixed set of slices,
// and report the labels, the time for each slice and the memory.
//
//   swift run model-check Models/openjev-4b-v5 --cases scripts/model-check-cases.jsonl --out results.jsonl
//
// With --log and --state, it reads a capture log from the app instead, and
// compares the model's label with the label the user selected (milestone 2).
// That output holds screen text: keep it on the Mac.
//
// The results file is the input of scripts/openjev_reference.py, which scores
// the same inputs with the Python reference.

struct Options {
  var model: URL
  var cases: URL?
  var log: URL?
  var state: URL?
  var out: URL?
  var limit = Int.max

  static func parse(_ args: [String]) -> Options? {
    guard let first = args.first, !first.hasPrefix("--") else { return nil }
    var options = Options(model: URL(fileURLWithPath: first))
    var rest = args.dropFirst().makeIterator()
    while let flag = rest.next() {
      guard let value = rest.next() else { return nil }
      switch flag {
      case "--cases": options.cases = URL(fileURLWithPath: value)
      case "--log": options.log = URL(fileURLWithPath: value)
      case "--state": options.state = URL(fileURLWithPath: value)
      case "--out": options.out = URL(fileURLWithPath: value)
      case "--limit": options.limit = Int(value) ?? Int.max
      default: return nil
      }
    }
    guard (options.cases != nil) != (options.log != nil) else { return nil }
    guard options.log == nil || options.state != nil else { return nil }
    return options
  }
}

/// One slice to classify, and the label a person gave it.
struct Case {
  var name: String
  var expected: String
  var evidence: SliceEvidence
}

struct CaseLine: Decodable {
  var `case`: String
  var expected: String
  var evidence: SliceEvidence
}

/// One line of the results file.
struct Result: Encodable {
  var `case`: String
  var expected: String
  var got: String
  var method: String
  var confidence: Double?
  var options: [String]
  var probabilities: [Double]
  var logits: [[Double]]
  var inputs: [String]
  var tokens: [[Int]]
  var sharedTokens: Int
  var milliseconds: Double
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

/// The memory macOS charges to this process, the figure Activity Monitor shows.
func footprintBytes() -> Int {
  var info = task_vm_info_data_t()
  var count = mach_msg_type_number_t(
    MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
  let status = withUnsafeMutablePointer(to: &info) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
    }
  }
  return status == KERN_SUCCESS ? Int(info.phys_footprint) : 0
}

func gigabytes(_ bytes: Int) -> String { String(format: "%.2f GB", Double(bytes) / 1e9) }

func lines(_ url: URL) -> [Substring] {
  guard let text = try? String(contentsOf: url, encoding: .utf8) else {
    fail("Cannot read \(url.path)")
  }
  return text.split(separator: "\n").filter { !$0.allSatisfy(\.isWhitespace) }
}

func loadCases(_ options: Options) -> (cases: [Case], allocations: [Allocation], fromLog: Bool) {
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  if let url = options.cases {
    let cases = lines(url).map { line -> Case in
      guard let c = try? decoder.decode(CaseLine.self, from: Data(line.utf8)) else {
        fail("Not a case line: \(line.prefix(80))")
      }
      return Case(name: c.case, expected: c.expected, evidence: c.evidence)
    }
    return (cases, Allocation.starterSet, false)
  }
  guard let stateURL = options.state, let logURL = options.log,
    let state = try? decoder.decode(SavedState.self, from: Data(contentsOf: stateURL))
  else { fail("Cannot read the state file") }
  func name(_ label: SliceLabel) -> String {
    switch label {
    case .allocation(let id): state.allocations.first { $0.id == id }?.name ?? "Removed allocation"
    case .unassigned: "Unassigned"
    case .idle: "Idle"
    }
  }
  var cases: [Case] = []
  for line in lines(logURL) {
    guard let record = try? decoder.decode(SliceRecord.self, from: Data(line.utf8)) else {
      continue
    }
    // Only minutes count. An idle slice needs no model.
    guard record.trigger == .minute, record.label != .idle else { continue }
    cases.append(
      Case(
        name: record.time.formatted(.iso8601), expected: name(record.userLabel),
        evidence: record.evidence))
  }
  return (cases, state.allocations, true)
}

guard let options = Options.parse(Array(CommandLine.arguments.dropFirst())) else {
  fail(
    """
    usage: model-check <model-folder> --cases <cases.jsonl> [--out <results.jsonl>] [--limit N]
           model-check <model-folder> --log <slices.jsonl> --state <state.json> [--out <results.jsonl>]
    """)
}

let (cases, allocations, fromLog) = loadCases(options)
let classifier = SliceClassifier(rules: SliceRules(), allocations: allocations, pinnedRules: [])
let names: [SliceLabel: String] = Dictionary(
  uniqueKeysWithValues: allocations.map { (.allocation($0.id), $0.name) } + [
    (.unassigned, "Unassigned"), (.idle, "Idle"),
  ])

let footprintBefore = footprintBytes()
let loadStart = Date()
let model: JevModel
do {
  model = try await JevModel(folder: options.model)
} catch {
  fail("The model did not load: \(error.localizedDescription)")
}
let loadSeconds = Date().timeIntervalSince(loadStart)
print("Model \(model.name) loaded in \(String(format: "%.1f", loadSeconds)) s.")

var output: FileHandle?
if let out = options.out {
  FileManager.default.createFile(
    atPath: out.path, contents: nil, attributes: [.posixPermissions: 0o600])
  output = try FileHandle(forWritingTo: out)
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

var times: [Double] = []
var right = 0
var counted = 0
var previous: PreviousSlice?
for c in cases.prefix(options.limit) {
  // The capture log keeps step 3, as in the app. The fixed cases are each
  // scored by the model.
  let step = classifier.start(c.evidence, previous: fromLog ? previous : nil)
  var result = Result(
    case: c.name, expected: c.expected, got: "", method: "", options: [], probabilities: [],
    logits: [], inputs: [], tokens: [], sharedTokens: 0, milliseconds: 0)
  let decision: SliceDecision
  switch step {
  case .drop:
    continue
  case .decided(let d):
    decision = d
  case .askModel(let request):
    let inputs = request.inputs
    let start = Date()
    let logits = try await model.logits(for: inputs)
    let ms = Date().timeIntervalSince(start) * 1000
    times.append(ms)
    let probabilities = Decision.optionProbabilities(logits: logits)
    decision = classifier.finish(request, probabilities: probabilities)
    let tokens = await model.tokens(for: inputs)
    result.options = request.options.map(\.name)
    result.probabilities = probabilities ?? []
    result.logits = logits
    result.inputs = inputs
    result.tokens = tokens
    result.sharedTokens = TokenPrefix.sharedLength(tokens)
    result.milliseconds = ms
  }
  previous = PreviousSlice(evidence: c.evidence, decision: decision)
  result.got = names[decision.label] ?? "Removed allocation"
  result.method = "\(decision.method)"
  result.confidence = decision.confidence
  if c.expected != "Idle" {
    counted += 1
    if result.got == c.expected { right += 1 }
  }
  let confidence = decision.confidence.map { String(format: "%.2f", $0) } ?? "-"
  let mark = result.got == c.expected ? "ok " : "NO "
  print(
    "\(mark) \(c.name.padding(toLength: 26, withPad: " ", startingAt: 0)) expected \(c.expected), got \(result.got) (\(confidence), \(result.method))"
  )
  if let output { try output.write(contentsOf: try encoder.encode(result) + Data("\n".utf8)) }
}
try output?.close()

let sorted = times.sorted()
print("")
print(
  "Slices: \(counted). Same as the expected label: \(right) (\(counted == 0 ? 0 : 100 * right / counted)%)."
)
if !sorted.isEmpty {
  let mean = sorted.reduce(0, +) / Double(sorted.count)
  print(
    String(
      format:
        "Model time per slice: mean %.0f ms, median %.0f ms, slowest %.0f ms (%d model runs).",
      mean, sorted[sorted.count / 2], sorted.last!, sorted.count))
}
print("Peak MLX memory: \(gigabytes(Memory.peakMemory)).")
print(
  "Process footprint: \(gigabytes(footprintBytes())), \(gigabytes(footprintBefore)) before the model loaded."
)
