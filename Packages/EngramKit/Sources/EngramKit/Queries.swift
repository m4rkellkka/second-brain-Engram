import Foundation
import GRDB

/// A project as `list_projects` shows it to Claude.
public struct ProjectSummary: Codable, Sendable, Equatable {
  public var slug: String
  public var name: String
  public var status: String?
  public var summary: String?
  public var entryCount: Int
}

/// `get_project_context`: the live context of one project.
public struct ProjectContext: Codable, Sendable, Equatable {
  public struct Line: Codable, Sendable, Equatable {
    public var text: String
    /// "claude" or "user".
    public var by: String
    public var fromNotes: Int
  }

  public var slug: String
  public var name: String
  public var status: String?
  public var summary: String?
  /// Who wrote the summary and status; the user's text is never replaced.
  public var summaryBy: String
  public var statusBy: String
  public var stack: [Line]
  public var decisions: [Line]
  public var ideas: [Line]
  public var openTasks: [EntryView]
  public var recentEntries: [EntryView]
}

/// A compact entry for tool results.
public struct EntryView: Codable, Sendable, Equatable {
  public var id: String
  public var kind: String
  public var content: String
  public var project: String?
  public var dueAt: String?
  public var done: Bool
  public var createdAt: String

  public init(_ item: InboxItem, timeZone: TimeZone = .current) {
    id = item.entry.id
    kind = item.entry.kind.rawValue
    content = item.entry.content
    project = item.project?.slug
    dueAt = item.entry.dueAt.map { LocalTime.due($0, in: timeZone) }
    done = item.entry.doneAt != nil
    createdAt = LocalTime.timestamp(item.entry.createdAt, in: timeZone)
  }
}

/// A typed thought waiting for Claude to sort it.
public struct UnsortedThought: Codable, Sendable, Equatable {
  public var captureId: String
  public var text: String
  public var createdAt: String
  public var timeZone: String
}

extension AppDatabase {
  public static func projectSummaries(_ db: Database) throws -> [ProjectSummary] {
    try fetchActiveProjects(db).map { project in
      ProjectSummary(
        slug: project.slug, name: project.name, status: project.status,
        summary: project.summary,
        entryCount: try Entry.filter(Column("project_id") == project.id).fetchCount(db))
    }
  }

  public static func projectContext(_ db: Database, slug: String) throws -> ProjectContext? {
    guard
      let project = try Project.filter(Column("slug") == slug && Column("archived_at") == nil)
        .fetchOne(db),
      let page = try projectPage(db, projectID: project.id)
    else { return nil }
    func lines(_ section: ContextSection) -> [ProjectContext.Line] {
      (page.sections[section] ?? []).map {
        .init(
          text: $0.item.text, by: $0.item.source == .user ? "user" : "claude",
          fromNotes: $0.sources.count)
      }
    }
    return ProjectContext(
      slug: project.slug, name: project.name, status: project.status, summary: project.summary,
      summaryBy: project.summarySource == .user ? "user" : "claude",
      statusBy: project.statusSource == .user ? "user" : "claude",
      stack: lines(.stack), decisions: lines(.decision), ideas: lines(.idea),
      openTasks: page.openTasks.map { EntryView($0) },
      recentEntries: page.recentEntries.prefix(20).map { EntryView($0) })
  }

  /// Open tasks, soonest due first; undated ones last.
  public static func openTasks(_ db: Database, projectSlug: String? = nil, dueBefore: Date? = nil)
    throws -> [InboxItem]
  {
    var request = Entry.including(optional: Entry.project).including(optional: Entry.capture)
      .filter(Column("kind") == EntryKind.task && Column("done_at") == nil)
    if let projectSlug {
      guard let project = try Project.filter(Column("slug") == projectSlug).fetchOne(db) else {
        return []
      }
      request = request.filter(Column("project_id") == project.id)
    }
    if let dueBefore { request = request.filter(Column("due_at") < dueBefore) }
    return try request.order(sql: "due_at is null, due_at, created_at desc").limit(100)
      .asRequest(of: InboxItem.self).fetchAll(db)
  }

  public static func unsortedThoughts(_ db: Database, limit: Int = 50) throws -> [UnsortedThought] {
    try Capture.filter(
      Column("source") == CaptureSource.typed && Column("status") == CaptureStatus.unsorted
    )
    .order(Column("created_at"))
    .limit(limit)
    .fetchAll(db)
    .map {
      UnsortedThought(
        captureId: $0.id, text: $0.rawText,
        createdAt: LocalTime.timestamp(
          $0.createdAt, in: TimeZone(identifier: $0.timeZone) ?? .current),
        timeZone: $0.timeZone)
    }
  }
}

extension AppDatabase {
  /// The date formats the tools accept, for filters like `dueBefore`.
  public static func parseDueDate(_ raw: String, timeZone: TimeZone) -> Date? {
    EntryRules.parseDate(raw, timeZone: timeZone)
  }
}
