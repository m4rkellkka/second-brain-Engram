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

/// `get_project_context` until the live context arrives in Phase 8.
public struct ProjectContext: Codable, Sendable, Equatable {
  public var slug: String
  public var name: String
  public var status: String?
  public var summary: String?
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

  public init(_ item: InboxItem) {
    id = item.entry.id
    kind = item.entry.kind.rawValue
    content = item.entry.content
    project = item.project?.slug
    dueAt = item.entry.dueAt?.formatted(.iso8601)
    done = item.entry.doneAt != nil
    createdAt = item.entry.createdAt.formatted(.iso8601)
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
        .fetchOne(db)
    else { return nil }
    let base = Entry.including(optional: Entry.project).including(optional: Entry.capture)
      .filter(Column("project_id") == project.id)
    let tasks = try base.filter(Column("kind") == EntryKind.task && Column("done_at") == nil)
      .order(sql: "due_at is null, due_at, created_at desc")
      .asRequest(of: InboxItem.self).fetchAll(db)
    let recent = try base.order(Column("created_at").desc).limit(20)
      .asRequest(of: InboxItem.self).fetchAll(db)
    return ProjectContext(
      slug: project.slug, name: project.name, status: project.status, summary: project.summary,
      openTasks: tasks.map(EntryView.init), recentEntries: recent.map(EntryView.init))
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
        captureId: $0.id, text: $0.rawText, createdAt: $0.createdAt.formatted(.iso8601),
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
