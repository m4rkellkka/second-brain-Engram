import Foundation
import GRDB

extension AppDatabase {
  /// Entries sharing at least this many keywords get a link for the graph.
  static let minSharedKeywords = 2

  /// Links a new entry to older ones it shares keywords with. The weight is
  /// the shared share of the smaller keyword set (0…1).
  static func linkByKeywords(_ entry: Entry, _ db: Database) throws {
    let mine = Set(entry.keywords?.split(separator: " ").map(String.init) ?? [])
    guard mine.count >= minSharedKeywords else { return }
    let others = try Row.fetchAll(
      db, sql: "select id, keywords from entries where keywords is not null and id != ?",
      arguments: [entry.id])
    for row in others {
      let otherID: String = row["id"]
      let theirs = Set((row["keywords"] as String).split(separator: " ").map(String.init))
      let shared = mine.intersection(theirs).count
      guard shared >= minSharedKeywords else { continue }
      let weight = Double(shared) / Double(min(mine.count, theirs.count))
      try db.execute(
        sql: "insert or ignore into entry_links (source_id, target_id, weight) values (?, ?, ?)",
        arguments: [entry.id, otherID, weight])
    }
  }
}
