import Foundation
import GRDB
import Testing

@testable import EngramKit

@Suite struct ReviewTests {
  func claudeEntry(_ db: AppDatabase, suggested: String? = nil) throws -> String {
    let result = try db.saveFromClaude(
      SaveRequest(
        summary: "Review \(UUID().uuidString).",
        entries: [
          EntryInput(kind: "idea", content: "Unsure", suggestedProject: suggested, confidence: 0.4)
        ]))
    return try #require(result.entries.first?.id)
  }

  func corrections(_ db: AppDatabase) throws -> [String] {
    try db.writer.read {
      try String.fetchAll($0, sql: "select field from entry_corrections order by rowid")
    }
  }

  @Test func confirmClearsReviewAndIsRecorded() throws {
    let db = try AppDatabase.inMemory()
    let id = try claudeEntry(db)
    try db.confirmEntry(id)
    #expect(try db.writer.read { try Entry.fetchOne($0, key: id) }?.needsReview == false)
    #expect(try corrections(db) == ["confirmed"])
  }

  @Test func pickingAProjectSettlesTheCard() throws {
    let db = try AppDatabase.inMemory()
    let project = try db.createProject(named: "Engram")
    let id = try claudeEntry(db)
    try db.setProject(project.id, forEntry: id)
    let entry = try #require(try db.writer.read { try Entry.fetchOne($0, key: id) })
    #expect(entry.projectId == project.id)
    #expect(entry.needsReview == false)
    #expect(try corrections(db) == ["project"])
  }

  @Test func kindChangeIsRecorded() throws {
    let db = try AppDatabase.inMemory()
    let id = try claudeEntry(db)
    try db.setKind(.task, forEntry: id)
    #expect(try db.writer.read { try Entry.fetchOne($0, key: id) }?.kind == .task)
    #expect(try corrections(db) == ["kind"])
  }

  @Test func createsTheSuggestedProject() throws {
    let db = try AppDatabase.inMemory()
    let id = try claudeEntry(db, suggested: "Машина")
    try db.createSuggestedProject(forEntry: id)
    let item = try #require(try db.writer.read { try AppDatabase.fetchInbox($0) }.first)
    #expect(item.project?.name == "Машина")
    #expect(item.project?.slug == "mashina")
    #expect(item.entry.needsReview == false)
  }

  @Test func typedThoughtsAreNotCorrections() throws {
    let db = try AppDatabase.inMemory()
    let project = try db.createProject(named: "Engram")
    let note = try db.saveTypedThought("typed")
    try db.setProject(project.id, forEntry: note.id)
    try db.setKind(.task, forEntry: note.id)
    #expect(try corrections(db).isEmpty)
  }
}
