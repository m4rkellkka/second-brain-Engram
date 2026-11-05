import EngramKit
import Foundation
import MCP
import Testing

@testable import EngramMCP

@Suite struct ToolTests {
  func text(_ result: CallTool.Result) -> String {
    result.content.compactMap {
      if case .text(let text, _, _) = $0 { text } else { nil }
    }.joined()
  }

  @Test func everyToolHasAnObjectSchemaAndDescription() {
    let names = EngramTools.all.map(\.name)
    #expect(
      Set(names) == [
        "save_to_engram", "list_projects", "get_project_context", "search_entries", "list_tasks",
        "list_unsorted", "sort_capture", "update_project", "complete_task",
      ])
    for tool in EngramTools.all {
      #expect(tool.inputSchema.objectValue?["type"]?.stringValue == "object", "\(tool.name)")
      #expect((tool.description ?? "").count > 40, "\(tool.name)")
    }
  }

  @Test func saveThenSearchThroughTools() throws {
    let db = try AppDatabase.inMemory()
    _ = try db.createProject(named: "Engram")
    let save = EngramTools.call(
      "save_to_engram",
      arguments: [
        "summary": "Talked about the connector.",
        "entries": [
          [
            "kind": "task", "content": "Test the connector in Claude Desktop",
            "projectSlug": "engram", "confidence": 0.9, "keywords": ["коннектор", "connector"],
          ]
        ],
      ], database: db)
    #expect(save.isError == false)
    #expect(text(save).contains("\"project\":\"engram\""))

    let search = EngramTools.call("search_entries", arguments: ["query": "connector"], database: db)
    #expect(text(search).contains("Test the connector"))

    let tasks = EngramTools.call("list_tasks", arguments: ["projectSlug": "engram"], database: db)
    #expect(text(tasks).contains("Test the connector"))
  }

  @Test func badArgumentsComeBackAsErrors() throws {
    let db = try AppDatabase.inMemory()
    let missing = EngramTools.call("save_to_engram", arguments: ["summary": "x"], database: db)
    #expect(missing.isError == true)
    #expect(text(missing).contains("entries"))

    let wrong = EngramTools.call(
      "save_to_engram",
      arguments: ["summary": "x", "entries": [["kind": "memo", "content": "y"]]], database: db)
    #expect(wrong.isError == true)
    #expect(text(wrong).contains("entries[0].kind"))

    let unknown = EngramTools.call("get_project_context", arguments: ["slug": "nope"], database: db)
    #expect(unknown.isError == true)

    #expect(EngramTools.call("nope", arguments: nil, database: db).isError == true)
  }

  @Test func listProjectsGivesLocalTime() throws {
    let db = try AppDatabase.inMemory()
    _ = try db.createProject(named: "Engram")
    let zone = try #require(TimeZone(identifier: "Europe/Moscow"))
    let now = try #require(ISO8601DateFormatter().date(from: "2026-11-06T09:30:00Z"))
    let result = EngramTools.call(
      "list_projects", arguments: nil, database: db, now: now, timeZone: zone)
    #expect(text(result).contains("2026-11-06T12:30:00+03:00 (Friday)"))
    #expect(text(result).contains("\"slug\":\"engram\""))
  }

  @Test func unsortedThenSort() throws {
    let db = try AppDatabase.inMemory()
    let note = try db.saveTypedThought("call the garage")
    let list = EngramTools.call("list_unsorted", arguments: nil, database: db)
    let captureID = try #require(note.captureId)
    #expect(text(list).contains(captureID))
    let sorted = EngramTools.call(
      "sort_capture",
      arguments: [
        "captureId": .string(captureID),
        "entries": [
          ["kind": "task", "content": "Call the garage", "confidence": 0.8, "keywords": []]
        ],
      ], database: db)
    #expect(sorted.isError == false)
  }

  @Test func saveWithContextUpdatesThenReadContext() throws {
    let db = try AppDatabase.inMemory()
    _ = try db.createProject(named: "Engram")
    let save = EngramTools.call(
      "save_to_engram",
      arguments: [
        "summary": "Decided on FTS5.",
        "entries": [
          [
            "kind": "note", "content": "Use FTS5", "projectSlug": "engram", "confidence": 1,
            "keywords": [],
          ]
        ],
        "contextUpdates": [
          [
            "projectSlug": "engram", "status": "Building search",
            "add": [["section": "decision", "text": "FTS5, no embeddings", "fromEntries": [0]]],
          ]
        ],
      ], database: db)
    #expect(save.isError == false)
    #expect(text(save).contains("\"added\":1"))

    let context = EngramTools.call(
      "get_project_context", arguments: ["slug": "engram"], database: db)
    #expect(text(context).contains("FTS5, no embeddings"))
    #expect(text(context).contains("Building search"))
  }

  @Test func updateProjectAndCompleteTaskWithoutNewEntries() throws {
    let db = try AppDatabase.inMemory()
    _ = try db.createProject(named: "Chess")
    let saved = try db.saveFromClaude(
      SaveRequest(
        summary: "Chess plan.",
        entries: [
          EntryInput(kind: "task", content: "Download PGNs", projectSlug: "chess", confidence: 1)
        ]))
    let taskID = try #require(saved.entries.first?.id)

    let update = EngramTools.call(
      "update_project",
      arguments: [
        "projectSlug": "chess", "summary": "A trainer for spotting threats.",
        "status": "Prototype test",
        "add": [
          ["section": "decision", "text": "No LLM in v1", "entryIds": .array([.string(taskID)])]
        ],
      ], database: db)
    #expect(update.isError == false)
    #expect(text(update).contains("\"summary\":\"updated\""))
    #expect(try db.writer.read { try Entry.fetchCount($0) } == 1)

    let context = EngramTools.call(
      "get_project_context", arguments: ["slug": "chess"], database: db)
    #expect(text(context).contains("No LLM in v1"))
    #expect(text(context).contains("\"fromNotes\":1"))

    let done = EngramTools.call(
      "complete_task", arguments: ["entryId": .string(taskID)], database: db)
    #expect(done.isError == false)
    #expect(try db.writer.read { try AppDatabase.openTasks($0) }.isEmpty)

    let reopened = EngramTools.call(
      "complete_task", arguments: ["entryId": .string(taskID), "done": false], database: db)
    #expect(reopened.isError == false)
    #expect(try db.writer.read { try AppDatabase.openTasks($0) }.count == 1)
  }

  @Test func completeTaskRejectsNonTasks() throws {
    let db = try AppDatabase.inMemory()
    let note = try db.saveTypedThought("just a note")
    let result = EngramTools.call(
      "complete_task", arguments: ["entryId": .string(note.id)], database: db)
    #expect(result.isError == true)
    #expect(text(result).contains("not a task"))
    let unknown = EngramTools.call(
      "update_project", arguments: ["projectSlug": "nope", "status": "x"], database: db)
    #expect(unknown.isError == true)
  }
}
