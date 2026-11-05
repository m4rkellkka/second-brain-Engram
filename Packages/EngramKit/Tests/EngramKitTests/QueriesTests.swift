import Foundation
import Testing

@testable import EngramKit

@Suite struct LocalTimeTests {
  let istanbul = TimeZone(identifier: "Europe/Istanbul")

  @Test func dateOnlyDeadlineReadsAsADate() throws {
    let zone = try #require(istanbul)
    let friday = try #require(EntryRules.parseDate("2026-11-06", timeZone: zone))
    #expect(LocalTime.due(friday, in: zone) == "2026-11-06")
  }

  @Test func timedDeadlineKeepsItsLocalOffset() throws {
    let zone = try #require(istanbul)
    let date = try #require(EntryRules.parseDate("2026-11-06T18:30:00+03:00", timeZone: zone))
    #expect(LocalTime.due(date, in: zone) == "2026-11-06T18:30:00+03:00")
    #expect(LocalTime.timestamp(date, in: zone) == "2026-11-06T18:30:00+03:00")
  }

  @Test func saveResultUsesTheCapturesZone() throws {
    let db = try AppDatabase.inMemory()
    let result = try db.saveFromClaude(
      SaveRequest(
        summary: "Due.", entries: [EntryInput(kind: "task", content: "x", dueAt: "2026-11-06")],
        timeZone: "Europe/Istanbul"))
    #expect(result.entries.first?.dueAt == "2026-11-06")
  }
}
