import Foundation
import GRDB

/// A row on the Projects list.
public struct ProjectOverview: Identifiable, Hashable, Sendable {
  public var project: Project
  public var openTasks: Int
  public var entryCount: Int
  /// The newest entry or context change, whichever is later.
  public var lastActivity: Date?
  public var id: String { project.id }
}

/// A context item with the entries it came from.
public struct ContextLine: Identifiable, Hashable, Sendable {
  public var item: ContextItem
  public var sources: [Entry]
  public var id: String { item.id }
}

/// Everything a project page shows.
public struct ProjectPage: Hashable, Sendable {
  public var project: Project
  public var sections: [ContextSection: [ContextLine]]
  public var openTasks: [InboxItem]
  public var doneTasks: [InboxItem]
  public var recentEntries: [InboxItem]
  /// Entries per kind in the whole project.
  public var kindCounts: [EntryKind: Int] = [:]
}

extension AppDatabase {
  /// Active projects by name, then archived ones.
  public static func projectOverviews(_ db: Database) throws -> [ProjectOverview] {
    let projects =
      try Project
      .order(sql: "archived_at is not null, name collate nocase")
      .fetchAll(db)
    return try projects.map { project in
      let stats = try Row.fetchOne(
        db,
        sql: """
          select
            count(*) as entries,
            coalesce(sum(kind = 'task' and done_at is null), 0) as open_tasks,
            max(created_at) as newest
          from entries where project_id = ?
          """, arguments: [project.id])
      let newest: Date? = stats?["newest"]
      let activity = [newest, project.contextUpdatedAt].compactMap { $0 }.max()
      return ProjectOverview(
        project: project, openTasks: stats?["open_tasks"] ?? 0, entryCount: stats?["entries"] ?? 0,
        lastActivity: activity)
    }
  }

  public static func projectPage(_ db: Database, projectID: String) throws -> ProjectPage? {
    guard let project = try Project.fetchOne(db, key: projectID) else { return nil }
    let items =
      try ContextItem
      .filter(Column("project_id") == projectID && Column("dismissed_at") == nil)
      .order(Column("created_at"), Column("rowid"))
      .fetchAll(db)
    let sourceIDs = Set(items.flatMap(\.entryIDList))
    let sources = Dictionary(
      uniqueKeysWithValues: try Entry.filter(keys: Array(sourceIDs)).fetchAll(db).map {
        ($0.id, $0)
      })
    var sections: [ContextSection: [ContextLine]] = [:]
    for item in items {
      sections[item.section, default: []].append(
        ContextLine(item: item, sources: item.entryIDList.compactMap { sources[$0] }))
    }

    let base = Entry.including(optional: Entry.project).including(optional: Entry.capture)
      .filter(Column("project_id") == projectID)
    let open = try base.filter(Column("kind") == EntryKind.task && Column("done_at") == nil)
      .order(sql: "due_at is null, due_at, created_at desc")
      .asRequest(of: InboxItem.self).fetchAll(db)
    let done = try base.filter(Column("kind") == EntryKind.task && Column("done_at") != nil)
      .order(Column("done_at").desc).limit(50)
      .asRequest(of: InboxItem.self).fetchAll(db)
    let recent = try base.filter(Column("kind") != EntryKind.task)
      .order(Column("created_at").desc, Column("rowid").desc).limit(30)
      .asRequest(of: InboxItem.self).fetchAll(db)
    var counts: [EntryKind: Int] = [:]
    for row in try Row.fetchAll(
      db, sql: "select kind, count(*) as n from entries where project_id = ? group by kind",
      arguments: [projectID])
    {
      if let kind = EntryKind(rawValue: row["kind"]) { counts[kind] = row["n"] }
    }
    return ProjectPage(
      project: project, sections: sections, openTasks: open, doneTasks: done, recentEntries: recent,
      kindCounts: counts)
  }

  public func projectOverviewUpdates() -> AsyncValueObservation<[ProjectOverview]> {
    ValueObservation.tracking(Self.projectOverviews).values(in: writer)
  }

  public func projectPageUpdates(_ projectID: String) -> AsyncValueObservation<ProjectPage?> {
    ValueObservation.tracking { try Self.projectPage($0, projectID: projectID) }.values(in: writer)
  }
}
