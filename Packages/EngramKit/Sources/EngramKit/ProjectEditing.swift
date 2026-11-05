import Foundation
import GRDB

/// Edits made by the user on a project page. Anything written here is
/// marked as the user's, and Claude's updates never replace it.
extension AppDatabase {
  public enum ProjectField: Sendable { case summary, status }

  /// Sets the summary or status by hand. An empty text clears it, still as the user's choice.
  public func setProjectText(
    _ field: ProjectField, to raw: String, projectID: String, now: Date = Date()
  ) throws {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let limit = field == .summary ? ContextRules.maxSummaryLength : ContextRules.maxStatusLength
    guard text.count <= limit else { throw EngramError.textTooLong(limit: limit) }
    try updateProject(projectID) { project in
      switch field {
      case .summary:
        project.summary = text.isEmpty ? nil : text
        project.summarySource = .user
      case .status:
        project.status = text.isEmpty ? nil : text
        project.statusSource = .user
      }
      project.contextUpdatedAt = now
    }
  }

  /// "Let Claude update": hands the field back to Claude's updates.
  public func handBackToClaude(_ field: ProjectField, projectID: String) throws {
    try updateProject(projectID) { project in
      switch field {
      case .summary: project.summarySource = .ai
      case .status: project.statusSource = .ai
      }
    }
  }

  public func renameProject(_ projectID: String, to raw: String) throws {
    let name = try ProjectNaming.validatedName(raw)
    try updateProject(projectID) { $0.name = name }
  }

  public func recolorProject(_ projectID: String, to color: String) throws {
    guard ProjectNaming.colors.contains(color.uppercased()) else { throw EngramError.unknownColor }
    try updateProject(projectID) { $0.color = color.uppercased() }
  }

  public func setArchived(_ archived: Bool, projectID: String, now: Date = Date()) throws {
    try updateProject(projectID) { $0.archivedAt = archived ? now : nil }
  }

  /// Adds an item by hand. If the same text was removed before, it comes back as the user's.
  public func addContextItem(
    _ section: ContextSection, text raw: String, projectID: String, now: Date = Date()
  ) throws {
    let text = try Self.validatedItemText(raw)
    try writer.write { db in
      guard try Project.exists(db, key: projectID) else { throw EngramError.projectNotFound }
      if var existing =
        try ContextItem
        .filter(Column("project_id") == projectID && Column("section") == section)
        .filter(sql: "lower(text) = lower(?)", arguments: [text])
        .fetchOne(db)
      {
        existing.dismissedAt = nil
        existing.source = .user
        try existing.update(db)
        return
      }
      try ContextItem(
        id: newID(), projectId: projectID, section: section, text: text, source: .user,
        entryIds: "[]", createdAt: now, dismissedAt: nil
      ).insert(db)
    }
  }

  public func editContextItem(_ itemID: String, text raw: String) throws {
    let text = try Self.validatedItemText(raw)
    try writer.write { db in
      guard var item = try ContextItem.fetchOne(db, key: itemID) else {
        throw EngramError.itemNotFound
      }
      item.text = text
      item.source = .user
      do {
        try item.update(db)
      } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
        throw EngramError.duplicateItem
      }
    }
  }

  /// Removes an item from the page and remembers it, so Claude won't add it again.
  public func dismissContextItem(_ itemID: String, now: Date = Date()) throws {
    try writer.write { db in
      guard var item = try ContextItem.fetchOne(db, key: itemID) else {
        throw EngramError.itemNotFound
      }
      item.dismissedAt = now
      try item.update(db)
    }
  }

  /// Ticks or unticks a task.
  public func setDone(_ done: Bool, entryID: String, now: Date = Date()) throws {
    try writer.write { db in
      var entry = try Self.entry(entryID, db)
      guard (entry.doneAt != nil) != done else { return }
      entry.doneAt = done ? now : nil
      entry.updatedAt = now
      try entry.update(db)
    }
  }

  private func updateProject(_ projectID: String, _ change: (inout Project) -> Void) throws {
    try writer.write { db in
      guard var project = try Project.fetchOne(db, key: projectID) else {
        throw EngramError.projectNotFound
      }
      change(&project)
      try project.update(db)
    }
  }

  static func validatedItemText(_ raw: String) throws -> String {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw EngramError.emptyText }
    guard text.count <= ContextRules.maxItemLength else {
      throw EngramError.textTooLong(limit: ContextRules.maxItemLength)
    }
    return text
  }
}
