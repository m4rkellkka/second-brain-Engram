import Foundation
import GRDB
import Testing

@testable import EngramKit

@Suite struct DatabaseTests {
  @Test func migrationCreatesEveryTable() throws {
    let db = try AppDatabase.inMemory()
    let tables = try db.writer.read { db in
      try String.fetchSet(db, sql: "select name from sqlite_master where type = 'table'")
    }
    for table in [
      "projects", "captures", "entries", "project_context_items", "entry_links",
      "entry_corrections", "entries_fts",
    ] {
      #expect(tables.contains(table), "missing \(table)")
    }
  }

  @Test func fileDatabaseUsesWALAndSurvivesReopening() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "engram-\(UUID().uuidString)", directoryHint: .isDirectory)
      .appending(path: "engram.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let first = try AppDatabase.open(at: url)
    try first.saveTypedThought("Survives a relaunch")
    let mode = try first.writer.read { try String.fetchOne($0, sql: "pragma journal_mode") }
    #expect(mode == "wal")

    let reopened = try AppDatabase.open(at: url)
    let items = try reopened.writer.read { try AppDatabase.fetchInbox($0) }
    #expect(items.map(\.entry.content) == ["Survives a relaunch"])
  }

  @Test func fullTextIndexFollowsEntries() throws {
    let db = try AppDatabase.inMemory()
    try db.saveTypedThought("Решил делать Engram на Swift")
    try db.saveTypedThought("Buy milk")
    let hits = try db.writer.read { db in
      try String.fetchAll(
        db,
        sql: """
          select entries.content from entries
          join entries_fts on entries_fts.rowid = entries.rowid
          where entries_fts match ?
          """, arguments: ["swift"])
    }
    #expect(hits == ["Решил делать Engram на Swift"])
  }

  @Test func sameClaudeSummaryCannotBeSavedTwice() throws {
    let db = try AppDatabase.inMemory()
    let now = Date()
    func claudeCapture() -> Capture {
      Capture(
        id: newID(), source: .claude, rawText: "Summary", conversationRef: nil,
        contentHash: AppDatabase.contentHash("Summary"), status: .sorted,
        timeZone: "Europe/Moscow", createdAt: now, sortedAt: now)
    }
    try db.writer.write { try claudeCapture().insert($0) }
    #expect(throws: DatabaseError.self) {
      try db.writer.write { try claudeCapture().insert($0) }
    }
  }
}
