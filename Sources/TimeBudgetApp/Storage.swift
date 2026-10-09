import Foundation
import TimeBudgetCore

/// Files in `~/Library/Application Support/TimeBudget/`. Nothing leaves the Mac.
struct Storage {
  let folder: URL
  var stateFile: URL { folder.appendingPathComponent("state.json") }
  var logFolder: URL { folder.appendingPathComponent("Slices", isDirectory: true) }

  static let standard = Storage(
    folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("TimeBudget", isDirectory: true))

  /// Only this user can read the folder: it holds text from the screen.
  func prepare() throws {
    for url in [folder, logFolder] {
      try FileManager.default.createDirectory(
        at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      // createDirectory does not change a folder that already exists.
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
  }

  enum LoadResult {
    case loaded(SavedState)
    case fresh
    /// The file did not decode. It moved to `movedTo`, so it is not lost.
    case unreadable(movedTo: URL, error: Error)
  }

  func loadState() -> LoadResult {
    guard let data = try? Data(contentsOf: stateFile) else { return .fresh }
    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return .loaded(try decoder.decode(SavedState.self, from: data))
    } catch {
      let stamp = Int(Date().timeIntervalSince1970)
      let aside = folder.appendingPathComponent("state.unreadable-\(stamp).json")
      try? FileManager.default.moveItem(at: stateFile, to: aside)
      return .unreadable(movedTo: aside, error: error)
    }
  }

  func save(_ state: SavedState) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(state).write(to: stateFile, options: [.atomic])
    // An atomic write replaces the file, with the default permissions.
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: stateFile.path)
  }

  func append(_ record: SliceRecord, calendar: Calendar) throws {
    let url = logFolder.appendingPathComponent(
      SliceLog.fileName(for: record.time, calendar: calendar))
    let line = try SliceLog.line(for: record)
    if !FileManager.default.fileExists(atPath: url.path) {
      guard
        FileManager.default.createFile(
          atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
      else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path]) }
    }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
  }

  /// Deletes log files past the retention window. Throws on the first file
  /// that cannot be listed or deleted.
  func deleteExpiredLogs(now: Date, calendar: Calendar) throws {
    let names = try FileManager.default.contentsOfDirectory(atPath: logFolder.path)
    for name in SliceLog.expired(names, now: now, calendar: calendar) {
      try FileManager.default.removeItem(at: logFolder.appendingPathComponent(name))
    }
  }

  /// The menu command "Delete all data" (spec "What the app stores").
  func deleteEverything() throws {
    if FileManager.default.fileExists(atPath: folder.path) {
      try FileManager.default.removeItem(at: folder)
    }
    try prepare()
  }
}
