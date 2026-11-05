import Foundation
import GRDB

extension AppDatabase {
  /// `save_to_engram`: stores a conversation summary and its entries in one
  /// transaction. Saving the same summary again returns the first save.
  public func saveFromClaude(_ request: SaveRequest, now: Date = Date()) throws -> SaveResult {
    let summary = request.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !summary.isEmpty else { throw InputError("summary: must not be empty.") }
    guard summary.count <= EntryRules.maxSummaryLength else {
      throw InputError("summary: keep it under \(EntryRules.maxSummaryLength) characters.")
    }
    let timeZone = request.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
    let hash = Self.contentHash(summary)

    return try writer.write { db in
      if let existing =
        try Capture
        .filter(Column("source") == CaptureSource.claude && Column("content_hash") == hash)
        .fetchOne(db)
      {
        return try Self.result(for: existing, duplicate: true, db)
      }

      let projects = try Self.fetchActiveProjects(db)
      let prepared = try EntryRules.prepare(request.entries, projects: projects, timeZone: timeZone)
      let updates = request.contextUpdates ?? []
      try ContextRules.validate(updates, entryCount: prepared.count)
      let capture = Capture(
        id: newID(), source: .claude, rawText: summary,
        conversationRef: request.conversationRef?.trimmingCharacters(in: .whitespacesAndNewlines),
        contentHash: hash, status: .sorted, timeZone: timeZone.identifier,
        createdAt: now, sortedAt: now)
      try capture.insert(db)
      let ids = try Self.insert(prepared, captureID: capture.id, now: now, db)
      let outcomes = try ContextRules.apply(updates, entryIDs: ids, now: now, db)
      return try Self.result(for: capture, duplicate: false, context: outcomes, db)
    }
  }

  /// `sort_capture`: replaces the placeholder note of a typed thought with
  /// the entries Claude made from it.
  public func sortCapture(
    _ captureID: String, entries: [EntryInput], contextUpdates: [ContextUpdateInput] = [],
    now: Date = Date()
  ) throws -> SaveResult {
    try writer.write { db in
      guard var capture = try Capture.fetchOne(db, key: captureID) else {
        throw InputError("captureId: no thought with this id; call list_unsorted first.")
      }
      guard capture.source == .typed, capture.status == .unsorted else {
        throw InputError("captureId: this thought is already sorted.")
      }
      let zone = TimeZone(identifier: capture.timeZone) ?? .current
      let projects = try Self.fetchActiveProjects(db)
      let prepared = try EntryRules.prepare(entries, projects: projects, timeZone: zone)
      try ContextRules.validate(contextUpdates, entryCount: prepared.count)

      try Entry.filter(Column("capture_id") == captureID).deleteAll(db)
      let ids = try Self.insert(prepared, captureID: captureID, now: capture.createdAt, db)
      let outcomes = try ContextRules.apply(contextUpdates, entryIDs: ids, now: now, db)
      capture.status = .sorted
      capture.sortedAt = now
      try capture.update(db)
      return try Self.result(for: capture, duplicate: false, context: outcomes, db)
    }
  }

  /// Inserts the entries in order and returns their ids.
  private static func insert(
    _ prepared: [EntryRules.Prepared], captureID: String, now: Date, _ db: Database
  ) throws -> [String] {
    var ids: [String] = []
    for item in prepared {
      let entry = Entry(
        id: newID(), captureId: captureID, projectId: item.projectID, kind: item.kind,
        content: item.content,
        keywords: item.keywords.isEmpty ? nil : item.keywords.joined(separator: " "),
        url: item.url, dueAt: item.dueAt, doneAt: nil, confidence: item.confidence,
        needsReview: item.needsReview, suggestedProject: item.suggestedProject,
        createdAt: now, updatedAt: now)
      try entry.insert(db)
      try linkByKeywords(entry, db)
      ids.append(entry.id)
    }
    return ids
  }

  private static func result(
    for capture: Capture, duplicate: Bool, context: [ContextOutcome]? = nil, _ db: Database
  ) throws -> SaveResult {
    let rows = try Entry.including(optional: Entry.project)
      .filter(Column("capture_id") == capture.id)
      .order(Column("rowid"))
      .asRequest(of: InboxItem.self)
      .fetchAll(db)
    let zone = TimeZone(identifier: capture.timeZone) ?? .current
    return SaveResult(
      captureId: capture.id, duplicate: duplicate,
      entries: rows.map { row in
        SaveResult.Saved(
          id: row.entry.id, kind: row.entry.kind.rawValue, content: row.entry.content,
          project: row.project?.slug, needsReview: row.entry.needsReview,
          dueAt: row.entry.dueAt.map { LocalTime.due($0, in: zone) })
      },
      context: context?.isEmpty == true ? nil : context)
  }
}
