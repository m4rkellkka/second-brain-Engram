import Foundation
import GRDB
import Testing

@testable import EngramKit

@Suite struct ContextUpdateTests {
  func setup() throws -> (AppDatabase, Project) {
    let db = try AppDatabase.inMemory()
    return (db, try db.createProject(named: "Engram"))
  }

  func save(
    _ db: AppDatabase, _ updates: [ContextUpdateInput], summary: String = UUID().uuidString
  ) throws -> SaveResult {
    try db.saveFromClaude(
      SaveRequest(
        summary: summary,
        entries: [
          EntryInput(kind: "note", content: "Use SQLite", projectSlug: "engram", confidence: 1),
          EntryInput(kind: "idea", content: "Weekly review", projectSlug: "engram", confidence: 1),
        ], contextUpdates: updates))
  }

  func page(_ db: AppDatabase, _ project: Project) throws -> ProjectPage {
    try #require(try db.writer.read { try AppDatabase.projectPage($0, projectID: project.id) })
  }

  @Test func addsItemsWithTheirSourcesAndSummary() throws {
    let (db, project) = try setup()
    let result = try save(
      db,
      [
        ContextUpdateInput(
          projectSlug: "engram", summary: "A local second brain.", status: "MVP",
          add: [
            .init(section: "stack", text: "SQLite", fromEntries: [0]),
            .init(section: "idea", text: "Weekly review", fromEntries: [1]),
          ])
      ])
    #expect(
      result.context == [
        ContextOutcome(
          project: "engram", added: 2, alreadyThere: 0, summary: "updated", status: "updated")
      ])
    let page = try page(db, project)
    #expect(page.project.summary == "A local second brain.")
    #expect(page.project.status == "MVP")
    #expect(page.sections[.stack]?.map(\.item.text) == ["SQLite"])
    #expect(page.sections[.stack]?.first?.sources.map(\.content) == ["Use SQLite"])
    #expect(page.sections[.idea]?.first?.item.source == .ai)
    #expect(page.kindCounts == [.note: 1, .idea: 1])
  }

  @Test func repeatsAreSkippedIgnoringCase() throws {
    let (db, project) = try setup()
    _ = try save(
      db,
      [ContextUpdateInput(projectSlug: "engram", add: [.init(section: "stack", text: "SQLite")])])
    let second = try save(
      db,
      [ContextUpdateInput(projectSlug: "engram", add: [.init(section: "stack", text: "sqlite")])])
    #expect(second.context?.first?.alreadyThere == 1)
    #expect(try page(db, project).sections[.stack]?.count == 1)
  }

  @Test func handEditedSummaryAndStatusSurvive() throws {
    let (db, project) = try setup()
    try db.setProjectText(.summary, to: "My own words.", projectID: project.id)
    try db.setProjectText(.status, to: "Paused", projectID: project.id)
    let result = try save(
      db, [ContextUpdateInput(projectSlug: "engram", summary: "Claude's take.", status: "Active")])
    #expect(result.context?.first?.summary == ContextRules.keptUserText)
    #expect(result.context?.first?.status == ContextRules.keptUserText)
    let saved = try page(db, project).project
    #expect(saved.summary == "My own words.")
    #expect(saved.status == "Paused")

    try db.handBackToClaude(.summary, projectID: project.id)
    _ = try save(db, [ContextUpdateInput(projectSlug: "engram", summary: "Claude's take.")])
    #expect(try page(db, project).project.summary == "Claude's take.")
    #expect(try page(db, project).project.status == "Paused")
  }

  @Test func removedItemsDoNotComeBack() throws {
    let (db, project) = try setup()
    _ = try save(
      db,
      [
        ContextUpdateInput(
          projectSlug: "engram", add: [.init(section: "decision", text: "Use FTS5")])
      ])
    let item = try #require(try page(db, project).sections[.decision]?.first)
    try db.dismissContextItem(item.id)
    let again = try save(
      db,
      [
        ContextUpdateInput(
          projectSlug: "engram", add: [.init(section: "decision", text: "Use FTS5")])
      ])
    #expect(again.context?.first?.added == 0)
    #expect(try page(db, project).sections[.decision] == nil)

    // Adding it by hand brings it back as the user's.
    try db.addContextItem(.decision, text: "use fts5", projectID: project.id)
    let back = try #require(try page(db, project).sections[.decision]?.first)
    #expect(back.item.source == .user)
  }

  @Test func badUpdatesAreRejectedWithTheEntries() throws {
    let (db, _) = try setup()
    let error = try #require(throws: InputError.self) {
      try save(
        db,
        [
          ContextUpdateInput(
            projectSlug: "engram",
            add: [
              .init(section: "risk", text: " "),
              .init(section: "idea", text: "x", fromEntries: [5]),
            ])
        ])
    }
    #expect(
      error.problems.contains("contextUpdates[0].add[0].section: use stack, decision or idea."))
    #expect(error.problems.contains("contextUpdates[0].add[0].text: must not be empty."))
    #expect(error.problems.contains { $0.contains("fromEntries: 5") })
    #expect(try db.writer.read { try Entry.fetchCount($0) } == 0)

    #expect(throws: InputError.self) {
      try save(db, [ContextUpdateInput(projectSlug: "nope", summary: "x")])
    }
    #expect(try db.writer.read { try Entry.fetchCount($0) } == 0)
  }

  @Test func fullContextForClaude() throws {
    let (db, _) = try setup()
    _ = try save(
      db,
      [
        ContextUpdateInput(
          projectSlug: "engram", summary: "S",
          add: [.init(section: "stack", text: "Swift", fromEntries: [0])])
      ])
    let context = try #require(
      try db.writer.read { try AppDatabase.projectContext($0, slug: "engram") })
    #expect(context.summaryBy == "claude")
    #expect(context.stack == [.init(text: "Swift", by: "claude", fromNotes: 1)])
    #expect(context.recentEntries.count == 2)
  }
}

@Suite struct ProjectEditingTests {
  @Test func editItemMakesItTheUsers() throws {
    let db = try AppDatabase.inMemory()
    let project = try db.createProject(named: "Engram")
    try db.addContextItem(.stack, text: "SwiftUI", projectID: project.id)
    try db.addContextItem(.stack, text: "GRDB", projectID: project.id)
    let items = try db.writer.read { try ContextItem.order(Column("rowid")).fetchAll($0) }
    try db.editContextItem(items[0].id, text: "SwiftUI + AppKit")
    #expect(
      try db.writer.read { try ContextItem.fetchOne($0, key: items[0].id) }?.text
        == "SwiftUI + AppKit")
    #expect(throws: EngramError.duplicateItem) { try db.editContextItem(items[0].id, text: "grdb") }
    #expect(throws: EngramError.emptyText) {
      try db.addContextItem(.idea, text: " ", projectID: project.id)
    }
  }

  @Test func renameRecolorArchive() throws {
    let db = try AppDatabase.inMemory()
    let project = try db.createProject(named: "Engram")
    try db.renameProject(project.id, to: "Engram App")
    try db.recolorProject(project.id, to: "#3fd0b6")
    #expect(throws: EngramError.unknownColor) { try db.recolorProject(project.id, to: "#000000") }
    try db.setArchived(true, projectID: project.id)

    let saved = try #require(try db.writer.read { try Project.fetchOne($0, key: project.id) })
    #expect(saved.name == "Engram App")
    #expect(saved.slug == "engram")  // links stay stable
    #expect(saved.color == "#3FD0B6")
    #expect(saved.archivedAt != nil)
    #expect(try db.writer.read { try AppDatabase.fetchActiveProjects($0) }.isEmpty)

    try db.setArchived(false, projectID: project.id)
    #expect(try db.writer.read { try AppDatabase.fetchActiveProjects($0) }.count == 1)
  }

  @Test func tickingATaskClosesIt() throws {
    let db = try AppDatabase.inMemory()
    _ = try db.createProject(named: "Engram")
    let result = try db.saveFromClaude(
      SaveRequest(
        summary: "t",
        entries: [EntryInput(kind: "task", content: "Ship", projectSlug: "engram", confidence: 1)]))
    let id = try #require(result.entries.first?.id)
    try db.setDone(true, entryID: id)
    #expect(try db.writer.read { try AppDatabase.openTasks($0) }.isEmpty)
    let overview = try db.writer.read(AppDatabase.projectOverviews)
    #expect(overview.first?.openTasks == 0)
    try db.setDone(false, entryID: id)
    #expect(try db.writer.read { try AppDatabase.openTasks($0) }.count == 1)
  }

  @Test func overviewsCountAndOrder() throws {
    let db = try AppDatabase.inMemory()
    let old = try db.createProject(named: "Zeta")
    _ = try db.createProject(named: "alpha")
    try db.setArchived(true, projectID: old.id)
    _ = try db.saveFromClaude(
      SaveRequest(
        summary: "o",
        entries: [
          EntryInput(kind: "task", content: "a", projectSlug: "alpha", confidence: 1),
          EntryInput(kind: "note", content: "b", projectSlug: "alpha", confidence: 1),
        ]))
    let rows = try db.writer.read(AppDatabase.projectOverviews)
    #expect(rows.map(\.project.name) == ["alpha", "Zeta"])
    #expect(rows[0].entryCount == 2)
    #expect(rows[0].openTasks == 1)
    #expect(rows[0].lastActivity != nil)
  }
}

@Suite struct BulkFilingTests {
  @Test func createFilesEveryEntryWithTheSameSuggestion() throws {
    let db = try AppDatabase.inMemory()
    let result = try db.saveFromClaude(
      SaveRequest(
        summary: "Chess.",
        entries: (0..<5).map {
          EntryInput(
            kind: "note", content: "Chess \($0)", suggestedProject: "Шахматный тренер",
            confidence: 0.9)
        } + [
          EntryInput(kind: "note", content: "Other", suggestedProject: "Машина", confidence: 0.9)
        ]))
    let first = try #require(result.entries.first?.id)
    let filed = try db.createSuggestedProject(forEntry: first)
    #expect(filed == 5)
    let items = try db.writer.read { try AppDatabase.fetchInbox($0) }
    #expect(items.filter { $0.project?.name == "Шахматный тренер" }.count == 5)
    #expect(items.filter(\.entry.needsReview).map(\.entry.content) == ["Other"])
  }
}
