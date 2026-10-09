import Foundation

/// Where the visible text of a slice came from.
public enum TextSource: String, Codable, Sendable {
  /// The macOS Accessibility API.
  case accessibility
  /// On-device text recognition on a screenshot.
  case textRecognition
  /// No text was read.
  case none
}

/// What the app saw at one moment (spec "Evidence for one slice").
public struct SliceEvidence: Codable, Equatable, Sendable {
  public var appName: String
  public var bundleID: String?
  public var windowTitle: String?
  /// The host part of the browser address, for example `github.com`.
  public var host: String?
  public var visibleText: String
  public var textSource: TextSource
  /// Text recognition on a screenshot, stored next to the Accessibility text
  /// for the capture test (milestone 2). Nil when it did not run.
  public var recognizedText: String?
  /// Why text recognition did not run or returned nothing, for the capture
  /// test. Nil when it ran, or when it was not wanted for this slice.
  public var recognitionNote: String?
  public var secondsSinceInput: Double

  public init(
    appName: String,
    bundleID: String? = nil,
    windowTitle: String? = nil,
    host: String? = nil,
    visibleText: String = "",
    textSource: TextSource = .none,
    recognizedText: String? = nil,
    secondsSinceInput: Double = 0
  ) {
    self.appName = appName
    self.bundleID = bundleID
    self.windowTitle = windowTitle
    self.host = host
    self.visibleText = visibleText
    self.textSource = textSource
    self.recognizedText = recognizedText
    self.secondsSinceInput = secondsSinceInput
  }

  /// True when the app, title, host and text are the same as in `other`.
  /// Idle time and recognized text are not part of the comparison (spec step
  /// 3, "Unchanged").
  public func sameContent(as other: SliceEvidence) -> Bool {
    appName == other.appName && bundleID == other.bundleID && windowTitle == other.windowTitle
      && host == other.host && visibleText == other.visibleText
  }
}

/// The label of one slice (spec F3).
public enum SliceLabel: Codable, Equatable, Sendable {
  case allocation(UUID)
  case unassigned
  case idle
}

/// Why a slice was taken.
public enum SliceTrigger: String, Codable, Sendable {
  /// The once-a-minute timer. Only these slices add time to the ledger.
  case minute
  /// The user switched to a different app.
  case appSwitch
}

/// One line of the capture log: the evidence, and the label the user gave it.
public struct SliceRecord: Codable, Equatable, Sendable {
  public var time: Date
  public var trigger: SliceTrigger
  public var label: SliceLabel
  /// The label the user had selected in the menu bar, before the idle rule.
  /// The capture test (milestone 2) compares classifiers against this.
  public var userLabel: SliceLabel
  /// The classifier's probability for `label`, from 0 to 1 (spec F3). Nil when
  /// no classifier ran: in this version the user sets the label by hand.
  public var confidence: Double?
  public var evidence: SliceEvidence

  public init(
    time: Date, trigger: SliceTrigger, label: SliceLabel, userLabel: SliceLabel,
    confidence: Double? = nil, evidence: SliceEvidence
  ) {
    precondition(confidence.map { (0...1).contains($0) } ?? true, "confidence is a probability")
    self.time = time
    self.trigger = trigger
    self.label = label
    self.userLabel = userLabel
    self.confidence = confidence
    self.evidence = evidence
  }
}

extension SliceRecord {
  private enum CodingKeys: String, CodingKey {
    case time, trigger, label, userLabel, confidence, evidence
  }

  /// Rejects a stored confidence that is not a probability.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
    if let confidence, !(0...1).contains(confidence) {
      throw DecodingError.dataCorruptedError(
        forKey: .confidence, in: c, debugDescription: "confidence \(confidence) is not in 0...1")
    }
    self.init(
      time: try c.decode(Date.self, forKey: .time),
      trigger: try c.decode(SliceTrigger.self, forKey: .trigger),
      label: try c.decode(SliceLabel.self, forKey: .label),
      userLabel: try c.decode(SliceLabel.self, forKey: .userLabel),
      confidence: confidence,
      evidence: try c.decode(SliceEvidence.self, forKey: .evidence))
  }
}
