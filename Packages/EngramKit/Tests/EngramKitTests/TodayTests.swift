import Foundation
import GRDB
import Testing

@testable import EngramKit

@Suite struct TodayTests {
  /// Istanbul is UTC+3 all year, so local midnight is 21:00 UTC.
  let zone = TimeZone(identifier: "Europe/Istanbul") ?? .current
  var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
  }

  func local(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
    let parts = DateComponents(
      timeZone: zone, year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second)
    return calendar.date(from: parts) ?? Date()
  }

  @Test func todayFollowsTheLocalDayNotUTC() throws {
    let db = try AppDatabase.inMemory()
    try db.saveTypedThought("late yesterday", now: local(5, 23, 59, 59))
    try db.saveTypedThought("just after midnight", now: local(6, 0, 0, 0))
    try db.saveTypedThought("late tonight", now: local(6, 23, 59, 59))
    try db.saveTypedThought("tomorrow", now: local(7, 0, 0, 0))

    let digest = try db.writer.read {
      try AppDatabase.today($0, now: local(6, 12), calendar: calendar)
    }
    #expect(digest.entries.map(\.entry.content) == ["late tonight", "just after midnight"])
    #expect(digest.day == local(6, 0))
  }

  @Test func digestCollectsWhatWaitsForTheUser() throws {
    let db = try AppDatabase.inMemory()
    let engram = try db.createProject(named: "Engram")
    let old = try db.createProject(named: "Old")
    let now = local(6, 12)
    try db.saveTypedThought("typed, unsorted", now: local(6, 9))
    _ = try db.saveFromClaude(
      SaveRequest(
        summary: "A chat.",
        entries: [
          EntryInput(kind: "idea", content: "Graph slider", projectSlug: "engram", confidence: 1),
          EntryInput(
            kind: "task", content: "Hand in the lab", projectSlug: "engram", dueAt: "2026-11-09",
            confidence: 1),
          EntryInput(
            kind: "task", content: "Far away", projectSlug: "engram", dueAt: "2026-12-20",
            confidence: 1),
          EntryInput(kind: "task", content: "Overdue", projectSlug: "engram", dueAt: "2026-11-01"),
          EntryInput(kind: "note", content: "Thesis topic", suggestedProject: "Диплом"),
          EntryInput(kind: "note", content: "Find a supervisor", suggestedProject: "диплом"),
          EntryInput(kind: "note", content: "No idea where", confidence: 0.2),
          EntryInput(kind: "note", content: "In an old project", projectSlug: "old", confidence: 1),
        ], timeZone: zone.identifier), now: now)
    try db.setArchived(true, projectID: old.id)

    let digest = try db.writer.read { try AppDatabase.today($0, now: now, calendar: calendar) }
    #expect(digest.entries.count == 9)
    #expect(digest.savedByClaude == 8)
    #expect(digest.unsorted == 1)
    #expect(digest.notSure.map(\.suggestion) == ["Диплом", nil])
    #expect(digest.notSure.first?.entries.count == 2)
    #expect(digest.waiting == 4)
    #expect(try db.writer.read(AppDatabase.waitingCount) == digest.waiting)
    // Due within a week, overdue first; the far one and done ones stay out.
    #expect(digest.dueSoon.map(\.entry.content) == ["Overdue", "Hand in the lab"])
    // Archived projects and their entries are left out.
    #expect(digest.projects.map(\.project.id) == [engram.id])
    #expect(digest.projects.first?.addedToday == 4)
    #expect(digest.totalEntries == 8)
  }

  @Test func emptyDatabaseGivesAnEmptyDigest() throws {
    let db = try AppDatabase.inMemory()
    let digest = try db.writer.read { try AppDatabase.today($0, calendar: calendar) }
    #expect(digest.entries.isEmpty)
    #expect(digest.waiting == 0)
    #expect(digest.projects.isEmpty)
  }
}
