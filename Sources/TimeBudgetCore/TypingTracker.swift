import Foundation

/// The focused text field at one moment, read through Accessibility. The app
/// never reads keystrokes: it compares the content of the field over time.
public struct FieldSnapshot: Equatable, Sendable {
  /// Identifies the field, so text from two fields is not compared.
  public var fieldID: String
  public var value: String
  /// Whether any key was pressed since the last snapshot. Text that appears
  /// with no key press came from somewhere else, such as a new chat message.
  public var keyPressed: Bool

  public init(fieldID: String, value: String, keyPressed: Bool) {
    self.fieldID = fieldID
    self.value = value
    self.keyPressed = keyPressed
  }
}

/// What the user typed in the last minute.
public struct TypedText: Equatable, Sendable {
  public var text: String
  /// All characters typed in the window, also those cut from `text`.
  public var characters: Int

  public init(text: String, characters: Int) {
    self.text = text
    self.characters = characters
  }
}

/// Finds the text the user typed, from snapshots of the focused field taken a
/// few seconds apart. The text stays in memory: it goes to the model and is
/// never written to disk.
///
/// A password field gives no snapshot: macOS hides its content from
/// Accessibility, and the reader skips it.
public struct TypingTracker: Sendable {
  /// Typed text older than this is forgotten.
  public static let window: TimeInterval = 60
  /// More text than this between two snapshots is a paste or program output,
  /// such as a terminal printing. Fast typing is about 10 characters a second.
  public static let maxInsertion = 300
  /// The most typed text that goes to the model.
  public static let textLimit = 1_000

  private struct Entry: Sendable {
    var time: Date
    var text: String
    /// True when this text continues the previous entry in the same field.
    var continues: Bool
  }

  private var last: FieldSnapshot?
  private var lastEntryField: String?
  private var entries: [Entry] = []

  public init() {}

  /// Adds one snapshot. Nil means no readable field: no focused field, a
  /// password field, or an excluded app or window. The next field then starts
  /// as a new baseline.
  public mutating func observe(_ snapshot: FieldSnapshot?, at time: Date) {
    entries.removeAll { time.timeIntervalSince($0.time) > Self.window }
    defer { last = snapshot }
    guard let snapshot, let last, last.fieldID == snapshot.fieldID, snapshot.keyPressed,
      let inserted = Self.insertion(old: last.value, new: snapshot.value),
      inserted.count <= Self.maxInsertion
    else { return }
    // An empty field before the insertion means a new message.
    let continues = lastEntryField == snapshot.fieldID && !last.value.isEmpty
    entries.append(Entry(time: time, text: inserted, continues: continues))
    lastEntryField = snapshot.fieldID
  }

  /// The text typed in the window before `time`, cut to the last `textLimit`
  /// characters.
  public func typed(at time: Date) -> TypedText {
    let recent = entries.filter { time.timeIntervalSince($0.time) <= Self.window }
    var text = ""
    for (index, entry) in recent.enumerated() {
      if index > 0 && !entry.continues { text += "\n" }
      text += entry.text
    }
    let characters = recent.reduce(0) { $0 + $1.text.count }
    return TypedText(text: String(text.suffix(Self.textLimit)), characters: characters)
  }

  public mutating func clear() {
    last = nil
    lastEntryField = nil
    entries = []
  }

  /// The text that `new` adds to `old`: the part between their shared start
  /// and their shared end. Nil when nothing was added.
  public static func insertion(old: String, new: String) -> String? {
    let a = Array(old)
    let b = Array(new)
    var prefix = 0
    while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < a.count - prefix, suffix < b.count - prefix,
      a[a.count - 1 - suffix] == b[b.count - 1 - suffix]
    {
      suffix += 1
    }
    let inserted = b[prefix..<(b.count - suffix)]
    return inserted.isEmpty ? nil : String(inserted)
  }
}
