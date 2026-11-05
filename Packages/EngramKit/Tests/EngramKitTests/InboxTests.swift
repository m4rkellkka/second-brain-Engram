import Foundation
import GRDB
import Testing

@testable import EngramKit

@Suite struct InboxTests {
  @Test func newestEntriesComeFirst() throws {
    let db = try AppDatabase.inMemory()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    for (i, text) in ["first", "second", "third"].enumerated() {
      try db.saveTypedThought(text, now: start.addingTimeInterval(Double(i)))
    }
    let items = try db.writer.read { try AppDatabase.fetchInbox($0) }
    #expect(items.map(\.entry.content) == ["third", "second", "first"])
  }

  @Test func sameSecondKeepsInsertOrder() throws {
    let db = try AppDatabase.inMemory()
    let now = Date()
    try db.saveTypedThought("older", now: now)
    try db.saveTypedThought("newer", now: now)
    let items = try db.writer.read { try AppDatabase.fetchInbox($0) }
    #expect(items.map(\.entry.content) == ["newer", "older"])
  }

  @Test func limitAndKindFilter() throws {
    let db = try AppDatabase.inMemory()
    for i in 0..<5 { try db.saveTypedThought("note \(i)") }
    try db.writer.write { db in
      try db.execute(sql: "update entries set kind = 'task' where content = 'note 0'")
    }
    let limited = try db.writer.read { try AppDatabase.fetchInbox($0, limit: 3) }
    #expect(limited.count == 3)

    let tasks = try db.writer.read { try AppDatabase.fetchInbox($0, kind: .task) }
    #expect(tasks.map(\.entry.content) == ["note 0"])
  }

  @Test func itemsCarryTheirProject() throws {
    let db = try AppDatabase.inMemory()
    let entry = try db.saveTypedThought("Use GRDB")
    let project = try db.createProject(named: "Engram")
    try db.setProject(project.id, forEntry: entry.id)

    let items = try db.writer.read { try AppDatabase.fetchInbox($0) }
    #expect(items.first?.project?.name == "Engram")

    try db.setProject(nil, forEntry: entry.id)
    let cleared = try db.writer.read { try AppDatabase.fetchInbox($0) }
    #expect(cleared.first?.project == nil)
  }

  @Test func settingAnUnknownProjectFails() throws {
    let db = try AppDatabase.inMemory()
    let entry = try db.saveTypedThought("Orphan")
    #expect(throws: EngramError.projectNotFound) {
      try db.setProject("missing", forEntry: entry.id)
    }
    #expect(throws: EngramError.entryNotFound) {
      try db.setProject(nil, forEntry: "missing")
    }
  }

  @Test func deletingAProjectUnfilesItsEntries() throws {
    let db = try AppDatabase.inMemory()
    let entry = try db.saveTypedThought("Keep me")
    let project = try db.createProject(named: "Temp")
    try db.setProject(project.id, forEntry: entry.id)
    _ = try db.writer.write { try project.delete($0) }

    let items = try db.writer.read { try AppDatabase.fetchInbox($0) }
    #expect(items.map(\.entry.content) == ["Keep me"])
    #expect(items.first?.entry.projectId == nil)
  }
}
