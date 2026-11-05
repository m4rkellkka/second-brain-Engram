import Foundation
import GRDB

extension AppDatabase {
  /// Creates a project, or returns the active one that already has this name
  /// (ignoring case), so a double click never makes two.
  @discardableResult
  public func createProject(named raw: String, now: Date = Date()) throws -> Project {
    let name = try ProjectNaming.validatedName(raw)
    return try writer.write { db in
      let active = try Project.filter(Column("archived_at") == nil).fetchAll(db)
      if let existing = active.first(where: {
        $0.name.compare(name, options: .caseInsensitive) == .orderedSame
      }) {
        return existing
      }
      let all = try Project.fetchAll(db)
      let project = Project(
        id: newID(), name: name,
        slug: ProjectNaming.uniqueSlug(ProjectNaming.slugify(name), taken: all.map(\.slug)),
        color: ProjectNaming.pickColor(used: active.map(\.color)),
        status: nil, summary: nil, summarySource: .ai, statusSource: .ai,
        contextUpdatedAt: nil, archivedAt: nil, createdAt: now)
      try project.insert(db)
      return project
    }
  }

  /// Files an entry into a project, or takes it out of one (`nil`).
  public func setProject(_ projectID: String?, forEntry entryID: String, now: Date = Date())
    throws
  {
    try writer.write { db in
      guard var entry = try Entry.fetchOne(db, key: entryID) else {
        throw EngramError.entryNotFound
      }
      if let projectID, try Project.exists(db, key: projectID) == false {
        throw EngramError.projectNotFound
      }
      guard entry.projectId != projectID else { return }
      entry.projectId = projectID
      entry.updatedAt = now
      try entry.update(db)
    }
  }

  /// Active projects, by name.
  public static func fetchActiveProjects(_ db: Database) throws -> [Project] {
    try Project
      .filter(Column("archived_at") == nil)
      .order(Column("name").collating(.localizedCaseInsensitiveCompare))
      .fetchAll(db)
  }
}
