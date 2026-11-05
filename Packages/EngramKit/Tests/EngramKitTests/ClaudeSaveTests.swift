import Foundation
import GRDB
import Testing

@testable import EngramKit

@Suite struct ClaudeSaveTests {
  let moscow = TimeZone(identifier: "Europe/Moscow")

  func database() throws -> (AppDatabase, Project) {
    let db = try AppDatabase.inMemory()
    let engram = try db.createProject(named: "Engram")
    return (db, engram)
  }

  @Test func savesEntriesIntoProjects() throws {
    let (db, engram) = try database()
    let result = try db.saveFromClaude(
      SaveRequest(
        summary: "Discussed search for Engram.",
        entries: [
          EntryInput(
            kind: "note", content: "Search uses SQLite FTS5.", projectSlug: "engram",
            confidence: 0.95, keywords: ["поиск", "search", "FTS5"]),
          EntryInput(
            kind: "task", content: "Write search tests", projectSlug: "Engram",
            dueAt: "2026-11-07", confidence: 0.9),
        ],
        conversationRef: "Search chat", timeZone: "Europe/Moscow"))

    #expect(result.duplicate == false)
    #expect(result.entries.map(\.project) == ["engram", "engram"])
    #expect(result.entries.allSatisfy { !$0.needsReview })

    let capture = try #require(
      try db.writer.read { try Capture.fetchOne($0, key: result.captureId) })
    #expect(capture.source == .claude)
    #expect(capture.status == .sorted)
    #expect(capture.conversationRef == "Search chat")

    let entries = try db.writer.read { try Entry.order(Column("rowid")).fetchAll($0) }
    #expect(entries[0].projectId == engram.id)
    #expect(entries[0].keywords == "поиск search fts5")
    // Date-only due dates mean the start of that day in the user's zone.
    let expected = try #require(
      ISO8601DateFormatter().date(from: "2026-11-06T21:00:00Z"))
    #expect(entries[1].dueAt == expected)
  }

  @Test func unknownProjectOrLowConfidenceNeedsReview() throws {
    let (db, _) = try database()
    let result = try db.saveFromClaude(
      SaveRequest(
        summary: "Life admin.",
        entries: [
          EntryInput(
            kind: "task", content: "Book a car wash", projectSlug: "car",
            suggestedProject: "Машина", confidence: 0.9),
          EntryInput(
            kind: "idea", content: "Maybe a graph view", projectSlug: "engram", confidence: 0.4),
          EntryInput(kind: "note", content: "Unfiled thought", confidence: 0.9),
        ]))
    #expect(result.entries.map(\.needsReview) == [true, true, true])
    let suggestions = try db.writer.read {
      try String?.fetchAll($0, sql: "select suggested_project from entries order by rowid")
    }
    #expect(suggestions == ["Машина", nil, nil])
  }

  @Test func sameSummaryIsNotSavedTwice() throws {
    let (db, _) = try database()
    let request = SaveRequest(
      summary: "One summary.", entries: [EntryInput(kind: "note", content: "A", confidence: 1)])
    let first = try db.saveFromClaude(request)
    let second = try db.saveFromClaude(request)
    #expect(second.duplicate)
    #expect(second.captureId == first.captureId)
    #expect(try db.writer.read { try Entry.fetchCount($0) } == 1)
  }

  @Test func badInputListsEveryProblemAndSavesNothing() throws {
    let (db, _) = try database()
    let request = SaveRequest(
      summary: "Broken.",
      entries: [
        EntryInput(kind: "reminder", content: "  "),
        EntryInput(kind: "link", content: "Docs", url: "ftp://x"),
        EntryInput(kind: "task", content: "Soon", dueAt: "next week", confidence: 3),
      ])
    let error = try #require(throws: InputError.self) { try db.saveFromClaude(request) }
    #expect(error.problems.contains("entries[0].kind: use idea, task, note or link."))
    #expect(error.problems.contains("entries[0].content: must not be empty."))
    #expect(error.problems.contains("entries[1].url: must be an http or https link."))
    #expect(error.problems.contains { $0.hasPrefix("entries[2].dueAt") })
    #expect(error.problems.contains("entries[2].confidence: use a number from 0 to 1."))
    #expect(try db.writer.read { try Capture.fetchCount($0) } == 0)
  }

  @Test func emptySummaryOrNoEntriesIsRejected() throws {
    let (db, _) = try database()
    #expect(throws: InputError.self) {
      try db.saveFromClaude(
        SaveRequest(summary: " ", entries: [EntryInput(kind: "note", content: "x")]))
    }
    #expect(throws: InputError.self) {
      try db.saveFromClaude(SaveRequest(summary: "s", entries: []))
    }
  }

  @Test func entriesSharingKeywordsAreLinked() throws {
    let (db, _) = try database()
    _ = try db.saveFromClaude(
      SaveRequest(
        summary: "First.",
        entries: [
          EntryInput(
            kind: "note", content: "A", confidence: 1, keywords: ["swift", "grdb", "sqlite"])
        ]))
    _ = try db.saveFromClaude(
      SaveRequest(
        summary: "Second.",
        entries: [
          EntryInput(kind: "note", content: "B", confidence: 1, keywords: ["grdb", "SQLite"]),
          EntryInput(kind: "note", content: "C", confidence: 1, keywords: ["swift", "ui"]),
        ]))
    let links = try db.writer.read {
      try Row.fetchAll(
        $0,
        sql: """
          select s.content as source, t.content as target, weight from entry_links
          join entries s on s.id = source_id join entries t on t.id = target_id
          """)
    }
    #expect(links.count == 1)
    #expect(links.first?["source"] == "B")
    #expect(links.first?["target"] == "A")
    #expect(links.first?["weight"] == 1.0)
  }

  @Test func dateFormats() throws {
    let zone = try #require(moscow)
    let iso = ISO8601DateFormatter()
    #expect(
      EntryRules.parseDate("2026-11-07T18:00:00+03:00", timeZone: zone)
        == iso.date(from: "2026-11-07T15:00:00Z"))
    #expect(
      EntryRules.parseDate("2026-11-07T18:00", timeZone: zone)
        == iso.date(from: "2026-11-07T15:00:00Z"))
    #expect(
      EntryRules.parseDate("2026-11-07", timeZone: zone) == iso.date(from: "2026-11-06T21:00:00Z"))
    #expect(EntryRules.parseDate("Friday", timeZone: zone) == nil)
  }

  @Test func keywordsAreSplitLowercasedAndCapped() {
    let words = EntryRules.normalizeKeywords(
      ["Skate Park", "скейтпарк", "skate", "a", "b", "c", "d", "e", "f"])
    #expect(words == ["skate", "park", "скейтпарк", "a", "b", "c", "d", "e"])
  }
}

@Suite struct SortCaptureTests {
  @Test func replacesThePlaceholderNote() throws {
    let db = try AppDatabase.inMemory()
    _ = try db.createProject(named: "Engram")
    let note = try db.saveTypedThought("buy milk and finish the engram search")
    let captureID = try #require(note.captureId)

    let result = try db.sortCapture(
      captureID,
      entries: [
        EntryInput(kind: "task", content: "Buy milk", confidence: 0.9),
        EntryInput(kind: "task", content: "Finish search", projectSlug: "engram", confidence: 0.9),
      ])
    #expect(result.entries.count == 2)
    let unsorted = try db.writer.read { try AppDatabase.unsortedThoughts($0) }
    #expect(unsorted.isEmpty)
    let contents = try db.writer.read {
      try String.fetchAll($0, sql: "select content from entries")
    }
    #expect(Set(contents) == ["Buy milk", "Finish search"])

    #expect(throws: InputError.self) {
      try db.sortCapture(captureID, entries: [EntryInput(kind: "note", content: "again")])
    }
  }

  @Test func unknownCaptureIsReported() throws {
    let db = try AppDatabase.inMemory()
    #expect(throws: InputError.self) {
      try db.sortCapture("missing", entries: [EntryInput(kind: "note", content: "x")])
    }
  }
}
