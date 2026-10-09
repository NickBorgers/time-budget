import Foundation

public enum TextTools {
  /// About 1,500 tokens at about 4 characters for each token (spec "Evidence
  /// for one slice").
  public static let visibleTextLimit = 6_000

  /// Joins text pieces into one block for the model. Trims each piece, drops
  /// empty pieces and repeats, and cuts the result at `limit` characters.
  public static func joinVisibleText(_ pieces: [String], limit: Int = visibleTextLimit) -> String {
    var seen = Set<String>()
    var lines: [String] = []
    var length = 0
    for piece in pieces {
      let line = piece.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      guard !line.isEmpty, seen.insert(line).inserted else { continue }
      let cost = line.count + (lines.isEmpty ? 0 : 1)
      if length + cost > limit {
        let room = limit - length - (lines.isEmpty ? 0 : 1)
        if room > 0 { lines.append(String(line.prefix(room))) }
        break
      }
      lines.append(line)
      length += cost
    }
    return lines.joined(separator: "\n")
  }

  /// Short form for the menu bar: `45m`, `1h 10m`, `20h`.
  public static func duration(minutes: Int) -> String {
    let hours = minutes / 60
    let rest = minutes % 60
    switch (hours, rest) {
    case (0, _): return "\(rest)m"
    case (_, 0): return "\(hours)h"
    default: return "\(hours)h \(rest)m"
    }
  }
}
