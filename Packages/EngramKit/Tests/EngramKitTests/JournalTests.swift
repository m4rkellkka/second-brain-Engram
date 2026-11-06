import Foundation
import GRDB
import Testing

@testable import EngramKit

@Suite struct JournalTests {
  /// Istanbul is UTC+3 all year, so local midnight is 21:00 UTC.
  let zone = TimeZone(identifier: "Europe/Istanbul") ?? .current
  var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
  }

  func local(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let parts = DateComponents(
      timeZone: zone, year: 2026, month: 11, day: day, hour: hour, minute: minute)
    return calendar.date(from: parts) ?? Date()
  }

  func write(
    _ db: AppDatabase, _ text: String, date: String? = nil, at now: Date
  ) throws -> JournalWriteResult {
    try db.writeJournalFromClaude(.init(text: text, date: date), now: now, calendar: calendar)
  }

  func page(_ db: AppDatabase, _ day: String) throws -> JournalPage? {
    try db.writer.read { try AppDatabase.journalPage($0, day: day, calendar: calendar) }
  }

  @Test func dayKeysFollowTheLocalDay() {
    #expect(JournalDate.key(local(6, 0, 0), calendar: calendar) == "2026-11-06")
    #expect(JournalDate.key(local(5, 23, 59), calendar: calendar) == "2026-11-05")
    #expect(JournalDate.start(of: "2026-11-06", calendar: calendar) == local(6, 0))
    for bad in ["2026-02-30", "2026-11-6", "26-11-06", "2026/11/06", "", "2026-11-06x"] {
      #expect(JournalDate.start(of: bad, calendar: calendar) == nil, "\(bad)")
    }
  }

  @Test func claudeWritesTodayInLocalTime() throws {
    let db = try AppDatabase.inMemory()
    // 00:30 in Istanbul is still the 5th in UTC.
    let result = try write(db, "Хороший день, переписал граф.", at: local(6, 0, 30))
    #expect(result == .init(date: "2026-11-06", duplicate: false, paragraphs: 1))
    let day = try #require(try page(db, "2026-11-06"))
    #expect(day.paragraphs.map(\.author) == [.claude])
    #expect(
      try db.writer.read { try JournalDay.fetchOne($0, key: "2026-11-06") }?.timeZone
        == "Europe/Istanbul")
  }

  @Test func claudeOnlyAppendsAndAHandEditSurvives() throws {
    let db = try AppDatabase.inMemory()
    _ = try write(db, "Устал после пар.", at: local(6, 19))
    let first = try #require(try page(db, "2026-11-06")?.paragraphs.first)
    try db.editJournalParagraph(first.id, text: "Устал после пар, но доволен.", now: local(6, 20))
    try db.addJournalParagraph(
      "Лягу пораньше.", day: "2026-11-06", now: local(6, 23), calendar: calendar)

    _ = try write(db, "Вечером ещё посидел над Engram.", at: local(6, 23, 30))

    let day = try #require(try page(db, "2026-11-06"))
    #expect(
      day.paragraphs.map(\.text) == [
        "Устал после пар, но доволен.", "Лягу пораньше.", "Вечером ещё посидел над Engram.",
      ])
    #expect(day.paragraphs.map(\.author) == [.claude, .user, .claude])
    #expect(day.paragraphs[0].editedAt == local(6, 20))
    #expect(day.paragraphs[2].editedAt == nil)
  }

  @Test func theSameParagraphFromClaudeIsSkipped() throws {
    let db = try AppDatabase.inMemory()
    _ = try write(db, "День как день.", at: local(6, 19))
    let again = try write(db, "  День как день.  ", at: local(6, 19, 5))
    #expect(again.duplicate)
    #expect(again.paragraphs == 1)
  }

  @Test func pastDaysAreAllowedFutureDaysAreNot() throws {
    let db = try AppDatabase.inMemory()
    let yesterday = try write(db, "Вчера был сложный день.", date: "2026-11-05", at: local(6, 9))
    #expect(yesterday.date == "2026-11-05")
    #expect(try page(db, "2026-11-05")?.paragraphs.first?.createdAt == local(6, 9))

    #expect(throws: InputError.self) {
      _ = try write(db, "Завтра будет хорошо.", date: "2026-11-07", at: self.local(6, 9))
    }
    #expect(throws: EngramError.futureDay) {
      try db.addJournalParagraph(
        "x", day: "2026-11-07", now: self.local(6, 9), calendar: self.calendar)
    }
  }

  @Test func badInputIsRejectedWithReasons() throws {
    let db = try AppDatabase.inMemory()
    do {
      _ = try write(db, "   ", date: "вчера", at: local(6, 9))
      Issue.record("expected an error")
    } catch let error as InputError {
      #expect(error.problems.count == 2)
      #expect(error.description.contains("text"))
      #expect(error.description.contains("YYYY-MM-DD"))
    }
    let long = String(repeating: "a", count: AppDatabase.maxJournalLength + 1)
    #expect(throws: InputError.self) { _ = try write(db, long, at: self.local(6, 9)) }
    #expect(throws: EngramError.emptyText) {
      try db.addJournalParagraph(
        " \n", day: "2026-11-06", now: self.local(6, 9), calendar: self.calendar)
    }
    #expect(try db.writer.read { try JournalParagraph.fetchCount($0) } == 0)
  }

  @Test func clearingTheLastParagraphRemovesTheDay() throws {
    let db = try AppDatabase.inMemory()
    let paragraph = try db.addJournalParagraph(
      "Тест", day: "2026-11-06", now: local(6, 9), calendar: calendar)
    try db.editJournalParagraph(paragraph.id, text: "  ", now: local(6, 10))
    #expect(try db.writer.read { try JournalDay.fetchCount($0) } == 0)
    #expect(try page(db, "2026-11-06")?.paragraphs.isEmpty == true)
  }

  @Test func rangeDefaultsToTheLastWeekAndIsCapped() throws {
    let now = local(6, 12)
    let week = try AppDatabase.journalRange(from: nil, to: nil, now: now, calendar: calendar)
    #expect(week == ("2026-10-31", "2026-11-06"))
    let clamped = try AppDatabase.journalRange(
      from: "2026-11-01", to: "2026-12-01", now: now, calendar: calendar)
    #expect(clamped == ("2026-11-01", "2026-11-06"))
    #expect(throws: InputError.self) {
      _ = try AppDatabase.journalRange(
        from: "2026-01-01", to: "2026-11-06", now: now, calendar: self.calendar)
    }
    #expect(throws: InputError.self) {
      _ = try AppDatabase.journalRange(
        from: "2026-11-06", to: "2026-11-01", now: now, calendar: self.calendar)
    }
  }

  @Test func exportGroupsParagraphsByDayInLocalTime() throws {
    let db = try AppDatabase.inMemory()
    _ = try write(db, "Понедельник.", date: "2026-11-02", at: local(2, 22))
    _ = try write(db, "Среда, утро.", at: local(4, 9))
    try db.addJournalParagraph(
      "Среда, вечер.", day: "2026-11-04", now: local(4, 22), calendar: calendar)
    _ = try write(db, "Слишком давно.", date: "2026-10-01", at: local(4, 23))

    let export = try db.writer.read {
      try AppDatabase.journalExport(
        $0, from: "2026-10-31", to: "2026-11-06", timeZone: zone, calendar: calendar)
    }
    #expect(export.days.map(\.date) == ["2026-11-02", "2026-11-04"])
    #expect(export.days.map(\.weekday) == ["Monday", "Wednesday"])
    #expect(export.days[1].paragraphs.map(\.author) == ["claude", "user"])
    #expect(export.days[1].paragraphs[0].writtenAt == "2026-11-04T09:00:00+03:00")
  }

  @Test func pageShowsWhatWasSavedAndDoneThatDay() throws {
    let db = try AppDatabase.inMemory()
    let task = try db.saveTypedThought("отчёт по физике", now: local(3, 10))
    try db.setKind(.task, forEntry: task.id)
    try db.setDone(true, entryID: task.id, now: local(5, 18))
    try db.saveTypedThought("Metal вместо RealityKit", now: local(5, 0, 10))
    try db.saveTypedThought("поздно ночью", now: local(4, 23, 50))

    let day = try #require(try page(db, "2026-11-05"))
    #expect(day.entries.map(\.entry.content) == ["Metal вместо RealityKit"])
    #expect(day.done.map(\.entry.content) == ["отчёт по физике"])
  }

  @Test func listHasTodayJournalDaysAndSavedDays() throws {
    let db = try AppDatabase.inMemory()
    try db.saveTypedThought("a", now: local(3, 10))
    try db.saveTypedThought("b", now: local(3, 11))
    _ = try write(db, "Первый абзац.", date: "2026-11-04", at: local(4, 20))
    _ = try write(db, "Второй абзац.", date: "2026-11-04", at: local(4, 21))

    let days = try db.writer.read {
      try AppDatabase.journalDays($0, now: self.local(6, 12), calendar: self.calendar)
    }
    #expect(days.map(\.day) == ["2026-11-06", "2026-11-04", "2026-11-03"])
    #expect(days[1].preview == "Первый абзац.")
    #expect(days[2].saved == 2)
    #expect(days[0].preview == nil)
  }

  @Test func searchFindsDaysWithEitherSpellingOfYo() throws {
    let db = try AppDatabase.inMemory()
    _ = try write(db, "Ещё один длинный день, устал.", date: "2026-11-04", at: local(4, 22))
    _ = try write(db, "Опять устал после пар.", date: "2026-11-05", at: local(5, 22))
    _ = try write(db, "И снова устал.", date: "2026-11-05", at: local(5, 23))

    let hits = try db.writer.read {
      try AppDatabase.searchJournal($0, query: "устал", calendar: self.calendar)
    }
    #expect(Set(hits.map(\.day)) == ["2026-11-04", "2026-11-05"])
    let yo = try db.writer.read {
      try AppDatabase.searchJournal($0, query: "еще", calendar: self.calendar)
    }
    #expect(yo.map(\.day) == ["2026-11-04"])

    let first = try #require(try page(db, "2026-11-04")?.paragraphs.first)
    try db.editJournalParagraph(first.id, text: "Спокойный день.", now: local(6, 9))
    let after = try db.writer.read {
      try AppDatabase.searchJournal($0, query: "еще", calendar: self.calendar)
    }
    #expect(after.isEmpty)
  }

  @Test func journalDaysAreGraphNodesLinkedToTheirEntries() throws {
    let db = try AppDatabase.inMemory()
    let engram = try db.createProject(named: "Engram")
    let saved = try db.saveTypedThought("граф на Metal", now: local(5, 16))
    try db.setProject(engram.id, forEntry: saved.id)
    try db.saveTypedThought("другой день", now: local(4, 16))
    _ = try write(db, "Хороший день.", date: "2026-11-05", at: local(5, 22))

    let graph = try db.writer.read { try AppDatabase.graph($0, calendar: self.calendar) }
    let day = try #require(graph.nodes.firstIndex { $0.journalDay == "2026-11-05" })
    #expect(graph.nodes[day].id == AppDatabase.journalNodeID("2026-11-05"))
    #expect(graph.nodes[day].content == "Хороший день.")
    let linked = graph.links.filter { $0.source == day }.map { graph.nodes[$0.target].content }
    #expect(linked == ["граф на Metal"])

    let layout = GraphLayout.compute(graph)
    #expect(layout.nodePositions.count == graph.nodes.count)
    #expect(layout.nodePositions[day].y > 0)
  }

  @Test func todayDigestCarriesTodaysJournal() throws {
    let db = try AppDatabase.inMemory()
    _ = try write(db, "Вчера.", date: "2026-11-05", at: local(6, 9))
    _ = try write(db, "Сегодня.", at: local(6, 10))
    let digest = try db.writer.read {
      try AppDatabase.today($0, now: self.local(6, 12), calendar: self.calendar)
    }
    #expect(digest.journal.map(\.text) == ["Сегодня."])
  }
}
