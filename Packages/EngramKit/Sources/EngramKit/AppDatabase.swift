import Foundation
import GRDB

/// The Engram database: one SQLite file, migrated on open.
///
/// The app and (from Phase 7) the `engram-mcp` helper open the same file,
/// so on disk it runs in WAL mode through a `DatabasePool`, which lets one
/// process write while others read.
public final class AppDatabase: Sendable {
  public let writer: any DatabaseWriter

  public init(_ writer: any DatabaseWriter) throws {
    self.writer = writer
    try Self.migrator.migrate(writer)
  }

  /// Opens (or creates) the database at `url`, creating its folder if needed.
  public static func open(at url: URL) throws -> AppDatabase {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    return try AppDatabase(DatabasePool(path: url.path))
  }

  /// `~/Library/Application Support/Engram/engram.sqlite`.
  public static func defaultURL() throws -> URL {
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    return support.appending(path: "Engram", directoryHint: .isDirectory)
      .appending(path: "engram.sqlite")
  }

  /// A fresh in-memory database, for tests and previews.
  public static func inMemory() throws -> AppDatabase {
    try AppDatabase(DatabaseQueue())
  }
}
