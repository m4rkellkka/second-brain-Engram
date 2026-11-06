import Foundation
import GRDB

public enum JournalAuthor: String, Codable, Sendable, DatabaseValueConvertible {
  case claude, user
}

/// One diary day, keyed by its local date (`2026-11-05`).
public struct JournalDay: EngramRecord, Hashable, Sendable {
  public static let databaseTableName = "journal_days"

  public var day: String
  public var timeZone: String
  public var createdAt: Date
  public var updatedAt: Date
}

/// A paragraph of a diary day. Claude only adds paragraphs; the user can
/// edit or remove any of them.
public struct JournalParagraph: EngramRecord, Identifiable, Hashable, Sendable {
  public static let databaseTableName = "journal_paragraphs"

  public var id: String
  public var day: String
  public var author: JournalAuthor
  public var text: String
  /// When the user last changed it (nil if never).
  public var editedAt: Date?
  public var createdAt: Date
}

/// Local days as `YYYY-MM-DD` keys.
public enum JournalDate {
  /// The key of the local day that contains `date`.
  public static func key(_ date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  /// Local midnight of the day `key` names, or nil if it isn't a real date.
  public static func start(of key: String, calendar: Calendar = .current) -> Date? {
    let parts = key.split(separator: "-", omittingEmptySubsequences: false)
    guard key.count == 10, parts.count == 3, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
    else { return nil }
    guard
      let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
      Self.key(date, calendar: calendar) == key
    else { return nil }
    return calendar.startOfDay(for: date)
  }

  /// The half-open interval `[midnight, next midnight)` of a day.
  static func interval(of key: String, calendar: Calendar) -> (start: Date, end: Date)? {
    guard let start = start(of: key, calendar: calendar) else { return nil }
    let end =
      calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    return (start, end)
  }

  static func adding(_ days: Int, to key: String, calendar: Calendar) -> String? {
    guard let start = start(of: key, calendar: calendar),
      let date = calendar.date(byAdding: .day, value: days, to: start)
    else { return nil }
    return Self.key(date, calendar: calendar)
  }
}

/// One day in the Journal tab's list.
public struct JournalListItem: Hashable, Sendable, Identifiable {
  public var day: String
  /// Local midnight of the day.
  public var date: Date
  /// The day's first paragraph, if anything was written.
  public var preview: String?
  /// Entries saved that day.
  public var saved: Int
  public var id: String { day }
}

/// What the Journal tab shows for one day.
public struct JournalPage: Hashable, Sendable {
  public var day: String
  public var date: Date
  public var paragraphs: [JournalParagraph]
  /// Entries saved that day, oldest first.
  public var entries: [InboxItem]
  /// Tasks ticked off that day (whenever they were saved).
  public var done: [InboxItem]
}

/// A diary day that matches a search, with its best paragraph.
public struct JournalHit: Hashable, Sendable, Identifiable {
  public var day: String
  public var date: Date
  public var paragraph: JournalParagraph
  public var id: String { day }
}

// MARK: - Claude

/// `write_journal`: one paragraph for a day, today when `date` is missing.
public struct JournalWriteInput: Codable, Sendable, Equatable {
  public var text: String
  public var date: String?

  public init(text: String, date: String? = nil) {
    self.text = text
    self.date = date
  }
}

public struct JournalWriteResult: Codable, Sendable, Equatable {
  public var date: String
  /// The same paragraph from Claude was already there, so nothing changed.
  public var duplicate: Bool
  /// Paragraphs on that day now, from anyone.
  public var paragraphs: Int
}

/// `get_journal` output: diary days in a range, oldest first.
public struct JournalExport: Codable, Sendable, Equatable {
  public struct Day: Codable, Sendable, Equatable {
    public var date: String
    public var weekday: String
    public var paragraphs: [Paragraph]
  }

  public struct Paragraph: Codable, Sendable, Equatable {
    /// Local time it was written.
    public var writtenAt: String
    /// "claude" or "user": who wrote it first.
    public var author: String
    public var editedByUser: Bool
    public var text: String
  }

  public var from: String
  public var to: String
  /// Days with no journal text are left out.
  public var days: [Day]
}

extension AppDatabase {
  public static let maxJournalLength = 4_000
  /// The longest range `get_journal` returns at once.
  public static let maxJournalRangeDays = 62

  /// Appends Claude's paragraph to a day. Never edits what is there: the
  /// user's text always survives a write from Claude.
  public func writeJournalFromClaude(
    _ input: JournalWriteInput, now: Date = Date(), calendar: Calendar = .current
  ) throws -> JournalWriteResult {
    var problems: [String] = []
    let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { problems.append("text: required, write what the user told you.") }
    if text.count > Self.maxJournalLength {
      problems.append("text: keep it under \(Self.maxJournalLength) characters.")
    }
    let today = JournalDate.key(now, calendar: calendar)
    var day = today
    if let raw = input.date?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
      if JournalDate.start(of: raw, calendar: calendar) == nil {
        problems.append("date: use YYYY-MM-DD, e.g. \(today).")
      } else if raw > today {
        problems.append("date: \(raw) is in the future; today is \(today).")
      } else {
        day = raw
      }
    }
    guard problems.isEmpty else { throw InputError(problems) }

    return try writer.write { db in
      let duplicate =
        try JournalParagraph
        .filter(Column("day") == day && Column("author") == JournalAuthor.claude)
        .filter(Column("text") == text)
        .fetchCount(db) > 0
      if !duplicate {
        try Self.append(
          db, text: text, day: day, author: .claude, timeZone: calendar.timeZone, now: now)
      }
      let count = try JournalParagraph.filter(Column("day") == day).fetchCount(db)
      return JournalWriteResult(date: day, duplicate: duplicate, paragraphs: count)
    }
  }

  /// Checks `get_journal`'s range: the last 7 days by default, never more
  /// than `maxJournalRangeDays`, and never past today.
  public static func journalRange(
    from: String?, to: String?, now: Date = Date(), calendar: Calendar = .current
  ) throws -> (from: String, to: String) {
    let today = JournalDate.key(now, calendar: calendar)
    var problems: [String] = []
    func parse(_ raw: String?, _ name: String) -> String? {
      guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
      guard JournalDate.start(of: raw, calendar: calendar) != nil else {
        problems.append("\(name): use YYYY-MM-DD, e.g. \(today).")
        return nil
      }
      return raw
    }
    let end = min(parse(to, "to") ?? today, today)
    let start =
      parse(from, "from") ?? JournalDate.adding(-6, to: end, calendar: calendar) ?? end
    guard problems.isEmpty else { throw InputError(problems) }
    guard start <= end else { throw InputError("from: must not be after to (\(end)).") }
    if let limit = JournalDate.adding(
      Self.maxJournalRangeDays - 1, to: start, calendar: calendar), end > limit
    {
      throw InputError("Ask for at most \(Self.maxJournalRangeDays) days at once.")
    }
    return (start, end)
  }

  /// Diary days between two keys (inclusive), as Claude reads them.
  public static func journalExport(
    _ db: Database, from: String, to: String, timeZone: TimeZone = .current,
    calendar: Calendar = .current
  ) throws -> JournalExport {
    let paragraphs =
      try JournalParagraph
      .filter(Column("day") >= from && Column("day") <= to)
      .order(Column("day"), Column("created_at"), Column("rowid"))
      .fetchAll(db)
    var days: [JournalExport.Day] = []
    for paragraph in paragraphs {
      let item = JournalExport.Paragraph(
        writtenAt: LocalTime.timestamp(paragraph.createdAt, in: timeZone),
        author: paragraph.author.rawValue, editedByUser: paragraph.editedAt != nil,
        text: paragraph.text)
      if days.last?.date == paragraph.day {
        days[days.count - 1].paragraphs.append(item)
      } else {
        let weekday =
          JournalDate.start(of: paragraph.day, calendar: calendar).map {
            $0.formatted(
              Date.FormatStyle(timeZone: calendar.timeZone).weekday(.wide)
                .locale(.init(identifier: "en_US")))
          } ?? ""
        days.append(.init(date: paragraph.day, weekday: weekday, paragraphs: [item]))
      }
    }
    return JournalExport(from: from, to: to, days: days)
  }

  // MARK: - The user

  /// Adds the user's own paragraph to a day (today or earlier).
  @discardableResult
  public func addJournalParagraph(
    _ raw: String, day: String, now: Date = Date(), calendar: Calendar = .current
  ) throws -> JournalParagraph {
    let text = try Self.checkedJournalText(raw)
    guard JournalDate.start(of: day, calendar: calendar) != nil else {
      throw EngramError.itemNotFound
    }
    guard day <= JournalDate.key(now, calendar: calendar) else { throw EngramError.futureDay }
    return try writer.write { db in
      try Self.append(
        db, text: text, day: day, author: .user, timeZone: calendar.timeZone, now: now)
    }
  }

  /// Replaces a paragraph's text with the user's; empty text removes it.
  public func editJournalParagraph(_ id: String, text raw: String, now: Date = Date()) throws {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return try deleteJournalParagraph(id) }
    let checked = try Self.checkedJournalText(text)
    try writer.write { db in
      guard var paragraph = try JournalParagraph.fetchOne(db, key: id) else {
        throw EngramError.itemNotFound
      }
      guard paragraph.text != checked else { return }
      paragraph.text = checked
      paragraph.editedAt = now
      try paragraph.update(db)
      try Self.touchDay(db, paragraph.day, now: now)
    }
  }

  /// Removes a paragraph, and the day with its last one.
  public func deleteJournalParagraph(_ id: String) throws {
    try writer.write { db in
      guard let paragraph = try JournalParagraph.fetchOne(db, key: id) else {
        throw EngramError.itemNotFound
      }
      try paragraph.delete(db)
      if try JournalParagraph.filter(Column("day") == paragraph.day).fetchCount(db) == 0 {
        _ = try JournalDay.deleteOne(db, key: paragraph.day)
      }
    }
  }

  static func checkedJournalText(_ raw: String) throws -> String {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw EngramError.emptyText }
    guard text.count <= maxJournalLength else {
      throw EngramError.textTooLong(limit: maxJournalLength)
    }
    return text
  }

  @discardableResult
  static func append(
    _ db: Database, text: String, day: String, author: JournalAuthor, timeZone: TimeZone,
    now: Date
  ) throws -> JournalParagraph {
    if try JournalDay.exists(db, key: day) {
      try touchDay(db, day, now: now)
    } else {
      try JournalDay(day: day, timeZone: timeZone.identifier, createdAt: now, updatedAt: now)
        .insert(db)
    }
    let paragraph = JournalParagraph(
      id: newID(), day: day, author: author, text: text, editedAt: nil, createdAt: now)
    try paragraph.insert(db)
    return paragraph
  }

  private static func touchDay(_ db: Database, _ day: String, now: Date) throws {
    try db.execute(
      sql: "update journal_days set updated_at = ? where day = ?", arguments: [now, day])
  }

  // MARK: - Reading

  /// Days for the Journal tab, newest first: today, every day with journal
  /// text and every day something was saved.
  public static func journalDays(
    _ db: Database, now: Date = Date(), calendar: Calendar = .current
  ) throws -> [JournalListItem] {
    var saved: [String: Int] = [:]
    for date in try Date.fetchAll(db, sql: "select created_at from entries") {
      saved[JournalDate.key(date, calendar: calendar), default: 0] += 1
    }
    var previews: [String: String] = [:]
    for row in try Row.fetchAll(
      db, sql: "select day, text from journal_paragraphs order by day, created_at, rowid")
    where previews[row["day"]] == nil {
      previews[row["day"]] = row["text"]
    }
    let keys = Set(saved.keys).union(previews.keys).union([JournalDate.key(now, calendar: calendar)]
    )
    return keys.sorted(by: >).compactMap { key in
      guard let date = JournalDate.start(of: key, calendar: calendar) else { return nil }
      return JournalListItem(day: key, date: date, preview: previews[key], saved: saved[key] ?? 0)
    }
  }

  /// One day: its paragraphs, what was saved and what got done.
  public static func journalPage(
    _ db: Database, day: String, calendar: Calendar = .current
  ) throws -> JournalPage? {
    guard let (start, end) = JournalDate.interval(of: day, calendar: calendar) else { return nil }
    let paragraphs = try paragraphs(db, day: day)
    func items(_ request: QueryInterfaceRequest<Entry>) throws -> [InboxItem] {
      try request.including(optional: Entry.project).including(optional: Entry.capture)
        .asRequest(of: InboxItem.self).fetchAll(db)
    }
    let entries = try items(
      Entry.filter(Column("created_at") >= start && Column("created_at") < end)
        .order(Column("created_at"), Column("rowid")))
    let done = try items(
      Entry.filter(Column("kind") == EntryKind.task)
        .filter(Column("done_at") >= start && Column("done_at") < end)
        .order(Column("done_at")))
    return JournalPage(
      day: day, date: start, paragraphs: paragraphs, entries: entries, done: done)
  }

  static func paragraphs(_ db: Database, day: String) throws -> [JournalParagraph] {
    try JournalParagraph.filter(Column("day") == day)
      .order(Column("created_at"), Column("rowid")).fetchAll(db)
  }

  /// Full-text search over the journal: one hit per day, best day first.
  public static func searchJournal(
    _ db: Database, query: String, limit: Int = 5, calendar: Calendar = .current
  ) throws -> [JournalHit] {
    guard let match = ftsQuery(query) else { return [] }
    let ids = try String.fetchAll(
      db,
      sql: """
        select p.id from journal_fts join journal_paragraphs p on p.rowid = journal_fts.rowid
        where journal_fts match ? order by bm25(journal_fts), p.created_at desc limit ?
        """, arguments: [match, limit * 4])
    let byID = Dictionary(
      uniqueKeysWithValues: try JournalParagraph.fetchAll(db, keys: ids).map { ($0.id, $0) })
    var seen: Set<String> = []
    var hits: [JournalHit] = []
    for id in ids {
      guard let paragraph = byID[id], !seen.contains(paragraph.day),
        let date = JournalDate.start(of: paragraph.day, calendar: calendar)
      else { continue }
      seen.insert(paragraph.day)
      hits.append(JournalHit(day: paragraph.day, date: date, paragraph: paragraph))
      if hits.count == limit { break }
    }
    return hits
  }

  // MARK: - Observations

  public func journalDaysUpdates(now: Date = Date(), calendar: Calendar = .current)
    -> AsyncValueObservation<[JournalListItem]>
  {
    ValueObservation.tracking { db in try Self.journalDays(db, now: now, calendar: calendar) }
      .values(in: writer)
  }

  public func journalPageUpdates(_ day: String, calendar: Calendar = .current)
    -> AsyncValueObservation<JournalPage?>
  {
    ValueObservation.tracking { db in try Self.journalPage(db, day: day, calendar: calendar) }
      .values(in: writer)
  }
}
