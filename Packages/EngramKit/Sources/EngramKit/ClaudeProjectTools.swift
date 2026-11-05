import Foundation
import GRDB

/// Result of `update_project`.
public struct ProjectUpdateResult: Codable, Sendable, Equatable {
  public var context: ContextOutcome
}

/// Result of `complete_task`.
public struct TaskResult: Codable, Sendable, Equatable {
  public var id: String
  public var content: String
  public var done: Bool
}

extension AppDatabase {
  /// `update_project`: updates a project's page without saving new entries.
  /// The same rules as `contextUpdates`: Claude only adds items, the user's
  /// summary and status are kept, removed items stay removed.
  public func updateProjectFromClaude(_ update: ContextUpdateInput, now: Date = Date()) throws
    -> ProjectUpdateResult
  {
    try ContextRules.validate([update], entryCount: 0)
    return try writer.write { db in
      let outcomes = try ContextRules.apply([update], entryIDs: [], now: now, db)
      guard let outcome = outcomes.first else { throw InputError("projectSlug: required.") }
      return ProjectUpdateResult(context: outcome)
    }
  }

  /// `complete_task`: ticks (or unticks) a task by its entry id.
  public func completeTaskFromClaude(_ entryID: String, done: Bool = true, now: Date = Date())
    throws -> TaskResult
  {
    let entry = try writer.read { db in try Entry.fetchOne(db, key: entryID) }
    guard let entry else {
      throw InputError("entryId: no entry with this id; find it with list_tasks.")
    }
    guard entry.kind == .task else {
      throw InputError("entryId: this entry is a \(entry.kind.rawValue), not a task.")
    }
    try setDone(done, entryID: entryID, now: now)
    return TaskResult(id: entry.id, content: entry.content, done: done)
  }
}
