import Foundation
import GRDB
import Testing

@testable import EngramKit

@Suite struct MarkdownExportTests {
  let zone = TimeZone(identifier: "Europe/Istanbul") ?? .current
  var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
  }

  func local(_ day: Int, _ hour: Int) -> Date {
    calendar.date(
      from: DateComponents(timeZone: zone, year: 2026, month: 11, day: day, hour: hour))
      ?? Date()
  }

  func files(_ db: AppDatabase) throws -> [String: String] {
    try db.writer.read { try MarkdownExport.files($0, timeZone: zone, calendar: calendar) }
  }

  /// Two linked entries in Engram, a task with a deadline, a link with
  /// quotes, an unfiled thought and a journal day.
  func seeded() throws -> AppDatabase {
    let db = try AppDatabase.inMemory()
    _ = try db.createProject(named: "Engram")
    _ = try db.saveFromClaude(
      SaveRequest(
        summary: "Graph work.",
        entries: [
          EntryInput(
            kind: "note", content: "Metal вместо RealityKit: нужны свои шейдеры",
            projectSlug: "engram", confidence: 0.9, keywords: ["metal", "шейдер", "граф"]),
          EntryInput(
            kind: "task", content: "Написать тест для шейдеров графа", projectSlug: "engram",
            dueAt: "2026-11-07", confidence: 0.9, keywords: ["тест", "шейдер", "граф"]),
          EntryInput(
            kind: "link", content: "Статья \"Metal by example\"", projectSlug: "engram",
            url: "https://metalbyexample.com", confidence: 0.9, keywords: ["metal"]),
        ]), now: local(5, 16))
    try db.saveTypedThought("купить хлеб", now: local(5, 18))
    _ = try db.writeJournalFromClaude(
      .init(text: "Хороший день, граф светится."), now: local(5, 22), calendar: calendar)
    return db
  }

  @Test func oneFilePerEntryWithFrontMatter() throws {
    let files = try files(seeded())
    let note = try #require(
      files.first { $0.key.hasPrefix("Engram/2026-11-05-metal-вместо-realitykit") })
    #expect(note.key.hasSuffix(".md"))
    #expect(note.value.hasPrefix("---\nid: \""))
    #expect(
      note.value.contains("kind: note\nproject: \"Engram\"\ncreated: 2026-11-05T16:00:00+03:00"))
    #expect(note.value.contains("keywords: [\"metal\", \"шейдер\", \"граф\"]"))
    #expect(note.value.contains("source: claude"))
    #expect(note.value.contains("\n---\n\nMetal вместо RealityKit: нужны свои шейдеры\n"))

    let task = try #require(files.first { $0.key.contains("написать-тест") })
    #expect(task.value.contains("due: 2026-11-07"))
    let link = try #require(files.first { $0.key.contains("статья") })
    #expect(link.value.contains("url: \"https://metalbyexample.com\""))
    #expect(link.value.contains("<https://metalbyexample.com>"))
    #expect(!link.key.contains("\""))
  }

  @Test func relatedEntriesAndTheirDayAreWikilinks() throws {
    let files = try files(seeded())
    let note = try #require(files.first { $0.key.contains("metal-вместо") })
    let task = try #require(files.first { $0.key.contains("написать-тест") })
    let taskName = String(task.key.dropFirst("Engram/".count).dropLast(3))
    #expect(note.value.contains("## Related\n\n- [[\(taskName)]]"))
    #expect(note.value.contains("Saved on [[2026-11-05]]."))
  }

  @Test func projectsInboxAndJournalGetTheirOwnFiles() throws {
    let files = try files(seeded())
    let readme = try #require(files["Engram/README.md"])
    #expect(readme.hasPrefix("# Engram\n"))
    #expect(readme.contains("## Entries\n\n- [["))
    #expect(files.keys.contains { $0.hasPrefix("Inbox/2026-11-05-купить-хлеб-") })
    let day = try #require(files["journal/2026-11-05.md"])
    #expect(
      day.contains("_2026-11-05T22:00:00+03:00 · from Claude_\n\nХороший день, граф светится."))
    #expect(day.contains("## On this day"))
  }

  @Test func namesAreSafeAndFoldersNeverCollide() throws {
    #expect(MarkdownExport.safeName("a/b: c? [d] #e\nf", limit: 40) == "a b c d e f")
    #expect(MarkdownExport.safeName("...hidden", limit: 40) == "hidden")
    #expect(MarkdownExport.safeName("one two three", limit: 7) == "one two")
    #expect(MarkdownExport.quoted("say \"hi\"\\") == "\"say \\\"hi\\\"\\\\\"")

    let db = try AppDatabase.inMemory()
    let inbox = try db.createProject(named: "Inbox")
    let slash = try db.createProject(named: "A/B")
    let other = try db.createProject(named: "A B")
    for project in [inbox, slash, other] {
      let entry = try db.saveTypedThought("note in \(project.name)", now: local(5, 10))
      try db.setProject(project.id, forEntry: entry.id)
    }
    let folders = Set(try files(db).keys.map { String($0.split(separator: "/")[0]) })
    #expect(folders == ["Inbox (inbox)", "A B", "A B (\(other.slug))"])
  }

  @Test func exportWritesANewFolderEachTime() throws {
    let db = try seeded()
    let parent = FileManager.default.temporaryDirectory
      .appending(path: "engram-export-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: parent) }
    let first = try db.exportMarkdown(into: parent, now: local(6, 9), calendar: calendar)
    let second = try db.exportMarkdown(into: parent, now: local(6, 9), calendar: calendar)
    #expect(first.lastPathComponent == "Engram Export 2026-11-06")
    #expect(second.lastPathComponent == "Engram Export 2026-11-06 2")
    let journal = first.appending(path: "journal/2026-11-05.md")
    #expect(FileManager.default.fileExists(atPath: journal.path))
  }
}
