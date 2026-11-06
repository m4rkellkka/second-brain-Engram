import Foundation
import GRDB

/// Everything in Engram as plain Markdown files, readable in any editor and
/// ready to open as an Obsidian vault:
///
/// - `<Project>/YYYY-MM-DD-<words>-<id>.md`: one entry per file, with YAML
///   front matter and `[[links]]` to related entries
/// - `<Project>/README.md`: the project's summary, status and live context
/// - `Inbox/`: entries not filed in a project
/// - `journal/YYYY-MM-DD.md`: one file per diary day
public enum MarkdownExport {
  /// Builds the files in memory: relative path → contents.
  public static func files(
    _ db: Database, timeZone: TimeZone = .current, calendar: Calendar = .current
  ) throws -> [String: String] {
    let projects = try Project.order(Column("created_at"), Column("rowid")).fetchAll(db)
    let entries = try Entry.order(Column("created_at"), Column("rowid")).fetchAll(db)
    let sources = Dictionary(
      try Capture.fetchAll(db).map { ($0.id, $0.source) }, uniquingKeysWith: { first, _ in first })
    let items = try ContextItem.filter(Column("dismissed_at") == nil)
      .order(Column("created_at"), Column("rowid")).fetchAll(db)
    let paragraphs = try JournalParagraph.order(
      Column("day"), Column("created_at"), Column("rowid")
    ).fetchAll(db)

    var related: [String: [(id: String, weight: Double)]] = [:]
    for row in try Row.fetchAll(db, sql: "select source_id, target_id, weight from entry_links") {
      let source: String = row["source_id"]
      let target: String = row["target_id"]
      let weight: Double = row["weight"]
      related[source, default: []].append((target, weight))
      related[target, default: []].append((source, weight))
    }

    // Folder names: the project's name made safe; reserved names and
    // repeats get the slug added, so no two projects share a folder.
    var folders: [String: String] = [:]
    var taken: Set<String> = ["inbox", "journal"]
    for project in projects {
      var name = safeName(project.name, limit: 60)
      if name.isEmpty || taken.contains(name.lowercased()) {
        name = (name.isEmpty ? "" : name + " ") + "(\(project.slug))"
      }
      taken.insert(name.lowercased())
      folders[project.id] = name
    }

    // Wikilinks use the file name without ".md", unique thanks to the id.
    var names: [String: String] = [:]
    for entry in entries {
      let day = JournalDate.key(entry.createdAt, calendar: calendar)
      var words = safeName(entry.content, limit: 48).lowercased()
        .split(separator: " ").joined(separator: "-")
      if words.isEmpty { words = entry.kind.rawValue }
      names[entry.id] = "\(day)-\(words)-\(entry.id.prefix(6))"
    }
    let projectByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
    let journalDays = Set(paragraphs.map(\.day))

    var files: [String: String] = [:]
    for entry in entries {
      guard let name = names[entry.id] else { continue }
      let folder = entry.projectId.flatMap { folders[$0] } ?? "Inbox"
      var front: [(String, String)] = [("id", quoted(entry.id)), ("kind", entry.kind.rawValue)]
      if let project = entry.projectId.flatMap({ projectByID[$0] }) {
        front.append(("project", quoted(project.name)))
      }
      front.append(("created", LocalTime.timestamp(entry.createdAt, in: timeZone)))
      if let due = entry.dueAt { front.append(("due", LocalTime.due(due, in: timeZone))) }
      if let done = entry.doneAt {
        front.append(("done", LocalTime.timestamp(done, in: timeZone)))
      }
      if let url = entry.url { front.append(("url", quoted(url))) }
      let keywords = entry.keywords?.split(separator: " ").map(String.init) ?? []
      if !keywords.isEmpty {
        front.append(("keywords", "[" + keywords.map(quoted).joined(separator: ", ") + "]"))
      }
      if let source = entry.captureId.flatMap({ sources[$0] }) {
        front.append(("source", source.rawValue))
      }
      if entry.needsReview { front.append(("needs_review", "true")) }

      var body = "---\n" + front.map { "\($0): \($1)" }.joined(separator: "\n") + "\n---\n\n"
      body += entry.content + "\n"
      if let url = entry.url, !entry.content.contains(url) { body += "\n<\(url)>\n" }
      let links = (related[entry.id] ?? [])
        .sorted { $0.weight > $1.weight }
        .compactMap { names[$0.id] }
      if !links.isEmpty {
        body += "\n## Related\n\n" + links.map { "- [[\($0)]]" }.joined(separator: "\n") + "\n"
      }
      let day = JournalDate.key(entry.createdAt, calendar: calendar)
      if journalDays.contains(day) { body += "\nSaved on [[\(day)]].\n" }
      files["\(folder)/\(name).md"] = body
    }

    for project in projects {
      guard let folder = folders[project.id] else { continue }
      var text = "# \(project.name)\n\n"
      if let status = project.status { text += "**Status:** \(status)\n\n" }
      if let summary = project.summary { text += summary + "\n\n" }
      if project.archivedAt != nil { text += "_Archived._\n\n" }
      for section in ContextSection.allCases {
        let lines = items.filter { $0.projectId == project.id && $0.section == section }
        if lines.isEmpty { continue }
        text +=
          "## \(section.title)\n\n" + lines.map { "- \($0.text)" }.joined(separator: "\n")
          + "\n\n"
      }
      let mine = entries.filter { $0.projectId == project.id }.compactMap { names[$0.id] }
      if !mine.isEmpty {
        text += "## Entries\n\n" + mine.map { "- [[\($0)]]" }.joined(separator: "\n") + "\n"
      }
      files["\(folder)/README.md"] = text
    }

    var days: [String: [JournalParagraph]] = [:]
    for paragraph in paragraphs { days[paragraph.day, default: []].append(paragraph) }
    for (day, list) in days {
      var text = "---\ndate: \(day)\n---\n\n# \(day)\n"
      for paragraph in list {
        let time = LocalTime.timestamp(paragraph.createdAt, in: timeZone)
        let author = paragraph.author == .claude ? "from Claude" : "you"
        let edited =
          paragraph.author == .claude && paragraph.editedAt != nil ? ", edited by you" : ""
        text += "\n_\(time) · \(author)\(edited)_\n\n\(paragraph.text)\n"
      }
      let saved = entries.filter { JournalDate.key($0.createdAt, calendar: calendar) == day }
        .compactMap { names[$0.id] }
      if !saved.isEmpty {
        text +=
          "\n## On this day\n\n" + saved.map { "- [[\($0)]]" }.joined(separator: "\n") + "\n"
      }
      files["journal/\(day).md"] = text
    }
    return files
  }

  /// A name that is safe as a file or folder name on macOS and in Obsidian
  /// (no slashes, colons, link or heading characters), on one line.
  static func safeName(_ text: String, limit: Int) -> String {
    let banned = Set("/\\:*?\"<>|#^[]{}`")
    let cleaned = String(text.map { banned.contains($0) || $0.isNewline ? " " : $0 })
    let words = cleaned.split(whereSeparator: \.isWhitespace)
    var result = ""
    for word in words {
      let next = result.isEmpty ? String(word) : result + " " + word
      if next.count > limit { break }
      result = next
    }
    if result.isEmpty, let first = words.first { result = String(first.prefix(limit)) }
    // A leading dot would hide the file.
    while result.hasPrefix(".") { result.removeFirst() }
    return result.trimmingCharacters(in: .whitespaces)
  }

  /// A YAML double-quoted string.
  static func quoted(_ text: String) -> String {
    let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
  }
}

extension AppDatabase {
  /// Writes the Markdown export into a new folder inside `parent` (named
  /// "Engram Export <date>", with a number if that exists) and returns it.
  @discardableResult
  public func exportMarkdown(
    into parent: URL, now: Date = Date(), timeZone: TimeZone = .current,
    calendar: Calendar = .current
  ) throws -> URL {
    let files = try writer.read {
      try MarkdownExport.files($0, timeZone: timeZone, calendar: calendar)
    }
    let manager = FileManager.default
    let base = "Engram Export \(JournalDate.key(now, calendar: calendar))"
    var folder = parent.appending(path: base, directoryHint: .isDirectory)
    var number = 2
    while manager.fileExists(atPath: folder.path) {
      folder = parent.appending(path: "\(base) \(number)", directoryHint: .isDirectory)
      number += 1
    }
    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
    for (path, contents) in files {
      let url = folder.appending(path: path)
      try manager.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(contents.utf8).write(to: url, options: .atomic)
    }
    return folder
  }
}
