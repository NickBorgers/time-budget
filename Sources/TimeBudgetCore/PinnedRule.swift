import Foundation

/// A rule that the user wrote, for example `Window title starts with
/// #partner- → Partner team help` (spec step 4). A rule runs before the model,
/// and its label is final.
public struct PinnedRule: Identifiable, Codable, Equatable, Sendable {
  public enum Field: String, Codable, CaseIterable, Sendable {
    /// The app name or its bundle identifier.
    case app
    case windowTitle
    /// The website host, for example `github.com`.
    case host
  }

  public enum Match: String, Codable, CaseIterable, Sendable {
    case contains
    case startsWith
    case equals
  }

  public let id: UUID
  public var field: Field
  public var match: Match
  public var text: String
  public var allocationID: UUID

  public init(id: UUID = UUID(), field: Field, match: Match, text: String, allocationID: UUID) {
    self.id = id
    self.field = field
    self.match = match
    self.text = text
    self.allocationID = allocationID
  }

  /// The condition in words, for the reason line: `window title starts with "#partner-"`.
  public var conditionText: String {
    let field =
      switch self.field {
      case .app: "app"
      case .windowTitle: "window title"
      case .host: "website"
      }
    let match =
      switch self.match {
      case .contains: "contains"
      case .startsWith: "starts with"
      case .equals: "is"
      }
    return "\(field) \(match) \"\(text.trimmingCharacters(in: .whitespacesAndNewlines))\""
  }

  /// Ignores case and the spaces around `text`. A rule with no text matches
  /// nothing, so a new, empty rule cannot take every slice.
  public func matches(_ evidence: SliceEvidence) -> Bool {
    let needle = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !needle.isEmpty else { return false }
    let values: [String?] =
      switch field {
      case .app: [evidence.appName, evidence.bundleID]
      case .windowTitle: [evidence.windowTitle]
      case .host: [evidence.host.map(ExcludeList.canonicalHost)]
      }
    return values.compactMap { $0?.lowercased() }.contains { value in
      switch match {
      case .contains: value.contains(needle)
      case .startsWith: value.hasPrefix(needle)
      case .equals: value == needle
      }
    }
  }
}
