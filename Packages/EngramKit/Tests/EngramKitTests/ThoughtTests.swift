import Foundation
import GRDB
import Testing

@testable import EngramKit

@Suite struct ThoughtTests {
  @Test func typedThoughtBecomesAnUnsortedNote() throws {
    let db = try AppDatabase.inMemory()
    let zone = try #require(TimeZone(identifier: "Europe/Moscow"))
    let entry = try db.saveTypedThought("  Позвонить в автосервис \n", timeZone: zone)

    #expect(entry.kind == .note)
    #expect(entry.content == "Позвонить в автосервис")
    #expect(entry.projectId == nil)
    #expect(entry.needsReview == false)

    let capture = try #require(
      try db.writer.read { try Capture.fetchOne($0, key: entry.captureId) })
    #expect(capture.source == .typed)
    #expect(capture.status == .unsorted)
    #expect(capture.rawText == "Позвонить в автосервис")
    #expect(capture.timeZone == "Europe/Moscow")
    #expect(capture.contentHash == AppDatabase.contentHash("Позвонить в автосервис"))
  }

  @Test func emptyThoughtIsRejected() throws {
    let db = try AppDatabase.inMemory()
    #expect(throws: EngramError.emptyThought) { try db.saveTypedThought("   \n ") }
    let count = try db.writer.read { try Capture.fetchCount($0) }
    #expect(count == 0)
  }

  @Test func overlongThoughtIsRejected() throws {
    let db = try AppDatabase.inMemory()
    let text = String(repeating: "a", count: AppDatabase.maxThoughtLength + 1)
    #expect(throws: EngramError.thoughtTooLong(limit: AppDatabase.maxThoughtLength)) {
      try db.saveTypedThought(text)
    }
  }

  @Test func sameTypedThoughtCanBeSavedTwice() throws {
    let db = try AppDatabase.inMemory()
    try db.saveTypedThought("Buy milk")
    try db.saveTypedThought("Buy milk")
    let count = try db.writer.read { try Entry.fetchCount($0) }
    #expect(count == 2)
  }
}
