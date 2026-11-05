import Foundation
import GRDB

/// A change to one project's live context, as Claude sends it with a save.
public struct ContextUpdateInput: Codable, Sendable, Equatable {
  public struct Item: Codable, Sendable, Equatable {
    public var section: String
    public var text: String
    /// Indexes into the `entries` of the same call that this item comes from.
    public var fromEntries: [Int]?
    /// Ids of saved entries it comes from (for `update_project`).
    public var entryIds: [String]?

    public init(
      section: String, text: String, fromEntries: [Int]? = nil, entryIds: [String]? = nil
    ) {
      self.section = section
      self.text = text
      self.fromEntries = fromEntries
      self.entryIds = entryIds
    }
  }

  public var projectSlug: String
  public var summary: String?
  public var status: String?
  public var add: [Item]?

  public init(
    projectSlug: String, summary: String? = nil, status: String? = nil, add: [Item]? = nil
  ) {
    self.projectSlug = projectSlug
    self.summary = summary
    self.status = status
    self.add = add
  }
}

/// What happened to one context update, so Claude can tell the user.
public struct ContextOutcome: Codable, Sendable, Equatable {
  public var project: String
  public var added: Int
  public var alreadyThere: Int
  /// "updated", "kept the user's text" or absent when not sent.
  public var summary: String?
  public var status: String?
}

enum ContextRules {
  static let maxSummaryLength = 600
  static let maxStatusLength = 80
  static let maxItemLength = 300
  static let maxItems = 20
  static let keptUserText = "kept the user's text"

  /// Checks the updates before anything is written.
  static func validate(_ updates: [ContextUpdateInput], entryCount: Int) throws(InputError) {
    var problems: [String] = []
    for (u, update) in updates.enumerated() {
      let at = "contextUpdates[\(u)]"
      if update.projectSlug.trimmingCharacters(in: .whitespaces).isEmpty {
        problems.append("\(at).projectSlug: required.")
      }
      if let summary = update.summary, summary.count > maxSummaryLength {
        problems.append("\(at).summary: keep it under \(maxSummaryLength) characters.")
      }
      if let status = update.status, status.count > maxStatusLength {
        problems.append("\(at).status: keep it under \(maxStatusLength) characters.")
      }
      let items = update.add ?? []
      if items.count > maxItems { problems.append("\(at).add: at most \(maxItems) items.") }
      for (i, item) in items.enumerated() {
        if ContextSection(rawValue: item.section.lowercased()) == nil {
          problems.append("\(at).add[\(i)].section: use stack, decision or idea.")
        }
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { problems.append("\(at).add[\(i)].text: must not be empty.") }
        if text.count > maxItemLength {
          problems.append("\(at).add[\(i)].text: keep it under \(maxItemLength) characters.")
        }
        for index in item.fromEntries ?? [] where !(0..<entryCount).contains(index) {
          problems.append(
            "\(at).add[\(i)].fromEntries: \(index) is not an entry index of this call.")
        }
      }
    }
    if !problems.isEmpty { throw InputError(problems) }
  }

  /// Applies validated updates inside the save's transaction. Claude only
  /// adds items and never overwrites what the user wrote.
  static func apply(
    _ updates: [ContextUpdateInput], entryIDs: [String], now: Date, _ db: Database
  ) throws -> [ContextOutcome] {
    var outcomes: [ContextOutcome] = []
    for update in updates {
      guard
        var project = EntryRules.match(
          update.projectSlug, in: try AppDatabase.fetchActiveProjects(db))
      else {
        throw InputError(
          "contextUpdates: no active project \"\(update.projectSlug)\"; use a slug from list_projects."
        )
      }
      var outcome = ContextOutcome(project: project.slug, added: 0, alreadyThere: 0)

      if let summary = clean(update.summary) {
        if project.summarySource == .user {
          outcome.summary = keptUserText
        } else {
          project.summary = summary
          outcome.summary = "updated"
        }
      }
      if let status = clean(update.status) {
        if project.statusSource == .user {
          outcome.status = keptUserText
        } else {
          project.status = status
          outcome.status = "updated"
        }
      }

      for item in update.add ?? [] {
        guard let section = ContextSection(rawValue: item.section.lowercased()),
          let text = clean(item.text)
        else { continue }
        let known = try Set(
          String.fetchAll(
            db,
            sql:
              "select id from entries where id in (\(databaseQuestionMarks(count: (item.entryIds ?? []).count)))",
            arguments: StatementArguments(item.entryIds ?? [])))
        let sources =
          (item.fromEntries ?? []).map { entryIDs[$0] }
          + (item.entryIds ?? []).filter { known.contains($0) }
        let row = ContextItem(
          id: newID(), projectId: project.id, section: section, text: text, source: .ai,
          entryIds: encode(sources), createdAt: now, dismissedAt: nil)
        // The unique index on (project, section, lower(text)) skips repeats,
        // including items the user removed.
        try row.insert(db, onConflict: .ignore)
        if db.changesCount > 0 { outcome.added += 1 } else { outcome.alreadyThere += 1 }
      }

      project.contextUpdatedAt = now
      try project.update(db)
      outcomes.append(outcome)
    }
    return outcomes
  }

  static func encode(_ ids: [String]) -> String {
    (try? String(decoding: JSONEncoder().encode(ids), as: UTF8.self)) ?? "[]"
  }

  static func clean(_ raw: String?) -> String? {
    guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}
