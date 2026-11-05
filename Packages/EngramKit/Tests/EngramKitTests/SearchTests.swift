import Foundation
import GRDB
import Testing

@testable import EngramKit

@Suite struct SearchTests {
  func seeded() throws -> AppDatabase {
    let db = try AppDatabase.inMemory()
    _ = try db.createProject(named: "Engram")
    _ = try db.createProject(named: "Учёба")
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    _ = try db.saveFromClaude(
      SaveRequest(
        summary: "Mixed.",
        entries: [
          EntryInput(
            kind: "note", content: "Купил новую клавиатуру", confidence: 1,
            keywords: ["клавиатура", "keyboard"]),
          EntryInput(
            kind: "note", content: "Engram search runs on FTS5", projectSlug: "engram",
            confidence: 1, keywords: ["поиск", "search"]),
          EntryInput(
            kind: "task", content: "Сдать отчёт по сетям", projectSlug: "ucheba", confidence: 1,
            keywords: ["отчёт", "сети"]),
        ]), now: start)
    return db
  }

  func search(_ db: AppDatabase, _ query: String, project: String? = nil, kind: EntryKind? = nil)
    throws -> [String]
  {
    try db.writer.read {
      try AppDatabase.search($0, query: query, projectSlug: project, kind: kind).map(
        \.entry.content)
    }
  }

  @Test func findsByPrefixAndKeywords() throws {
    let db = try seeded()
    #expect(try search(db, "FTS") == ["Engram search runs on FTS5"])
    #expect(try search(db, "keyboard") == ["Купил новую клавиатуру"])
    // "клавиатура" loses its final vowel, so it also finds "клавиатуру".
    #expect(try search(db, "клавиатура") == ["Купил новую клавиатуру"])
    #expect(try search(db, "отчет") == ["Сдать отчёт по сетям"])
  }

  @Test func everyWordMustMatch() throws {
    let db = try seeded()
    #expect(try search(db, "engram search") == ["Engram search runs on FTS5"])
    #expect(try search(db, "engram клавиатура").isEmpty)
  }

  @Test func filtersByProjectAndKind() throws {
    let db = try seeded()
    #expect(try search(db, "search", project: "ucheba").isEmpty)
    #expect(try search(db, "отчёт", kind: .task) == ["Сдать отчёт по сетям"])
    #expect(try search(db, "отчёт", kind: .note).isEmpty)
  }

  @Test func punctuationOnlyQueryFindsNothing() throws {
    let db = try seeded()
    #expect(try search(db, " \"*() ").isEmpty)
    #expect(AppDatabase.ftsQuery("a\"b") == "\"a\"* AND \"b\"*")
  }
}

@Suite struct QueryTests {
  @Test func openTasksAreSoonestFirstAndUndatedLast() throws {
    let db = try AppDatabase.inMemory()
    _ = try db.createProject(named: "Engram")
    _ = try db.saveFromClaude(
      SaveRequest(
        summary: "Tasks.",
        entries: [
          EntryInput(kind: "task", content: "Undated", projectSlug: "engram", confidence: 1),
          EntryInput(
            kind: "task", content: "Later", projectSlug: "engram", dueAt: "2026-12-01",
            confidence: 1),
          EntryInput(kind: "task", content: "Sooner", dueAt: "2026-11-10", confidence: 1),
          EntryInput(kind: "note", content: "Not a task", confidence: 1),
        ]))
    let all = try db.writer.read { try AppDatabase.openTasks($0) }.map(\.entry.content)
    #expect(all == ["Sooner", "Later", "Undated"])
    let engram = try db.writer.read { try AppDatabase.openTasks($0, projectSlug: "engram") }
    #expect(engram.map(\.entry.content) == ["Later", "Undated"])
    let cutoff = try #require(ISO8601DateFormatter().date(from: "2026-11-20T00:00:00Z"))
    let soon = try db.writer.read { try AppDatabase.openTasks($0, dueBefore: cutoff) }
    #expect(soon.map(\.entry.content) == ["Sooner"])
  }

  @Test func projectContextAndSummaries() throws {
    let db = try AppDatabase.inMemory()
    _ = try db.createProject(named: "Engram")
    _ = try db.saveFromClaude(
      SaveRequest(
        summary: "Ctx.",
        entries: [
          EntryInput(kind: "task", content: "Ship 0.7", projectSlug: "engram", confidence: 1),
          EntryInput(kind: "note", content: "Uses GRDB", projectSlug: "engram", confidence: 1),
        ]))
    let context = try #require(
      try db.writer.read { try AppDatabase.projectContext($0, slug: "engram") })
    #expect(context.openTasks.map(\.content) == ["Ship 0.7"])
    // Tasks are listed in openTasks, not again among the recent entries.
    #expect(context.recentEntries.map(\.content) == ["Uses GRDB"])
    #expect(try db.writer.read { try AppDatabase.projectContext($0, slug: "nope") } == nil)
    let summaries = try db.writer.read(AppDatabase.projectSummaries)
    #expect(summaries.map(\.entryCount) == [2])
  }
}
