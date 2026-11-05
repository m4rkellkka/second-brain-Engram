import Foundation
import GRDB

extension AppDatabase {
  /// Full-text search over entry text and keywords, best match first, newer
  /// first on ties. Every word must match the start of a word in the entry.
  public static func search(
    _ db: Database, query: String, projectSlug: String? = nil, kind: EntryKind? = nil,
    limit: Int = 20
  ) throws -> [InboxItem] {
    guard let match = ftsQuery(query) else { return [] }
    var sql = """
      select entries.id from entries_fts
      join entries on entries.rowid = entries_fts.rowid
      left join projects on projects.id = entries.project_id
      where entries_fts match ?
      """
    var arguments: StatementArguments = [match]
    if let projectSlug {
      sql += " and projects.slug = ?"
      _ = arguments.append(contentsOf: [projectSlug])
    }
    if let kind {
      sql += " and entries.kind = ?"
      _ = arguments.append(contentsOf: [kind.rawValue])
    }
    sql += " order by bm25(entries_fts), entries.created_at desc limit ?"
    _ = arguments.append(contentsOf: [limit])

    let ids = try String.fetchAll(db, sql: sql, arguments: arguments)
    guard !ids.isEmpty else { return [] }
    let items = try Entry.including(optional: Entry.project).including(optional: Entry.capture)
      .filter(keys: ids)
      .asRequest(of: InboxItem.self)
      .fetchAll(db)
    let rank = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
    return items.sorted { rank[$0.entry.id, default: 0] < rank[$1.entry.id, default: 0] }
  }

  /// `"word"*` for each word, joined with AND. Long Russian words lose a
  /// final vowel first, so "клавиатура" also finds "клавиатуру".
  static func ftsQuery(_ text: String) -> String? {
    let words = text.lowercased().replacingOccurrences(of: "ё", with: "е")
      .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      .map { word -> String in
        var word = String(word)
        if word.count >= 5, let last = word.last, "аеиоуыэюяйь".contains(last) {
          word.removeLast()
        }
        return "\"\(word)\"*"
      }
    return words.isEmpty ? nil : words.joined(separator: " AND ")
  }
}
