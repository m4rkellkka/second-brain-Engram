import Foundation
import GRDB

extension AppDatabase {
  public static let inboxLimit = 50

  /// Newest entries first, optionally of one kind, with their project.
  public static func fetchInbox(
    _ db: Database, kind: EntryKind? = nil, limit: Int = inboxLimit
  ) throws -> [InboxItem] {
    var request = Entry.including(optional: Entry.project)
    if let kind { request = request.filter(Column("kind") == kind) }
    return
      try request
      .order(Column("created_at").desc, Column("rowid").desc)
      .limit(limit)
      .asRequest(of: InboxItem.self)
      .fetchAll(db)
  }

  /// Inbox rows, re-emitted after every change to entries or projects.
  public func inboxUpdates(kind: EntryKind?, limit: Int = inboxLimit)
    -> AsyncValueObservation<[InboxItem]>
  {
    ValueObservation
      .tracking { db in try Self.fetchInbox(db, kind: kind, limit: limit) }
      .values(in: writer)
  }

  /// Active projects, re-emitted after every change.
  public func activeProjectUpdates() -> AsyncValueObservation<[Project]> {
    ValueObservation.tracking(Self.fetchActiveProjects).values(in: writer)
  }
}
