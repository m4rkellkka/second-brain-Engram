import Foundation
import GRDB

extension AppDatabase {
  /// "Looks right" on a "not sure" card.
  public func confirmEntry(_ entryID: String, now: Date = Date()) throws {
    try writer.write { db in
      var entry = try Self.entry(entryID, db)
      guard entry.needsReview else { return }
      entry.needsReview = false
      entry.updatedAt = now
      try entry.update(db)
      try Self.recordCorrection(entry, field: "confirmed", old: nil, new: "true", now: now, db)
    }
  }

  public func setKind(_ kind: EntryKind, forEntry entryID: String, now: Date = Date()) throws {
    try writer.write { db in
      var entry = try Self.entry(entryID, db)
      guard entry.kind != kind else { return }
      let old = entry.kind
      entry.kind = kind
      entry.updatedAt = now
      try entry.update(db)
      try Self.recordCorrection(
        entry, field: "kind", old: old.rawValue, new: kind.rawValue, now: now, db)
    }
  }

  /// Creates the project Claude suggested on a "not sure" card and files the entry there.
  public func createSuggestedProject(forEntry entryID: String, now: Date = Date()) throws {
    let suggestion = try writer.read { db in try Self.entry(entryID, db).suggestedProject }
    guard let suggestion else { throw EngramError.projectNotFound }
    let project = try createProject(named: suggestion, now: now)
    try setProject(project.id, forEntry: entryID, now: now)
  }

  static func entry(_ id: String, _ db: Database) throws -> Entry {
    guard let entry = try Entry.fetchOne(db, key: id) else { throw EngramError.entryNotFound }
    return entry
  }

  /// Remembers what the user changed after Claude sorted, to improve the
  /// tool descriptions later. Typed thoughts Claude never saw are skipped.
  static func recordCorrection(
    _ entry: Entry, field: String, old: String?, new: String?, now: Date, _ db: Database
  ) throws {
    guard let captureID = entry.captureId,
      let capture = try Capture.fetchOne(db, key: captureID), capture.status == .sorted
    else { return }
    try db.execute(
      sql: """
        insert into entry_corrections (id, entry_id, field, old_value, new_value, created_at)
        values (?, ?, ?, ?, ?, ?)
        """, arguments: [newID(), entry.id, field, old, new, now])
  }
}
