import Foundation
import GRDB

/// What the Today tab shows: the user's day at a glance.
public struct TodayDigest: Hashable, Sendable {
  /// "Not sure" entries that share Claude's suggested project.
  public struct NotSureGroup: Hashable, Sendable, Identifiable {
    /// The project Claude suggested, or nil when it had no idea.
    public var suggestion: String?
    public var entries: [InboxItem]
    public var id: String { suggestion?.lowercased() ?? "" }
  }

  /// An active project and how much landed in it today.
  public struct ProjectActivity: Hashable, Sendable, Identifiable {
    public var project: Project
    public var addedToday: Int
    public var entryCount: Int
    public var id: String { project.id }
  }

  /// Local midnight that starts the day.
  public var day: Date
  /// Entries created today, newest first.
  public var entries: [InboxItem]
  /// How many of today's entries Claude saved.
  public var savedByClaude: Int
  public var notSure: [NotSureGroup]
  /// Typed thoughts still waiting for Claude to sort them.
  public var unsorted: Int
  /// Open tasks due within the next week (overdue ones too), soonest first.
  public var dueSoon: [InboxItem]
  /// Active projects, busiest today first.
  public var projects: [ProjectActivity]
  /// Every entry the graph shows (archived projects left out).
  public var totalEntries: Int
  /// Today's journal paragraphs, oldest first.
  public var journal: [JournalParagraph] = []

  public static let empty = TodayDigest(
    day: .distantPast, entries: [], savedByClaude: 0, notSure: [], unsorted: 0, dueSoon: [],
    projects: [], totalEntries: 0)

  /// Everything that still needs the user: "not sure" entries and unsorted thoughts.
  public var waiting: Int { notSure.reduce(0) { $0 + $1.entries.count } + unsorted }
}

extension AppDatabase {
  public static let dueSoonDays = 7
  public static let dueSoonLimit = 5

  /// The digest for the local day that contains `now`. `calendar` carries
  /// the time zone, so "today" means the user's day, not the UTC one.
  public static func today(
    _ db: Database, now: Date = Date(), calendar: Calendar = .current
  ) throws -> TodayDigest {
    let start = calendar.startOfDay(for: now)
    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    let soon =
      calendar.date(byAdding: .day, value: dueSoonDays, to: end)
      ?? end.addingTimeInterval(Double(dueSoonDays) * 86_400)

    func items(_ request: QueryInterfaceRequest<Entry>) throws -> [InboxItem] {
      try request
        .including(optional: Entry.project)
        .including(optional: Entry.capture)
        .asRequest(of: InboxItem.self)
        .fetchAll(db)
    }

    let entries = try items(
      Entry
        .filter(Column("created_at") >= start && Column("created_at") < end)
        .order(Column("created_at").desc, Column("rowid").desc))

    let review = try items(
      Entry.filter(Column("needs_review") == true).order(Column("created_at").desc))
    var groups: [String: TodayDigest.NotSureGroup] = [:]
    var order: [String] = []
    for item in review {
      let suggestion = item.entry.suggestedProject?.trimmingCharacters(in: .whitespaces)
      let named = suggestion?.isEmpty == false ? suggestion : nil
      let key = named?.lowercased() ?? ""
      if groups[key] == nil {
        groups[key] = .init(suggestion: named, entries: [])
        order.append(key)
      }
      groups[key]?.entries.append(item)
    }

    let dueSoon = try items(
      Entry
        .filter(Column("kind") == EntryKind.task && Column("done_at") == nil)
        .filter(Column("due_at") != nil && Column("due_at") < soon)
        .order(Column("due_at"))
        .limit(dueSoonLimit))

    let unsorted =
      try Int.fetchOne(
        db,
        sql: """
          select count(*) from entries e join captures c on c.id = e.capture_id
          where c.source = 'typed' and c.status = 'unsorted'
          """) ?? 0

    let counts = try Row.fetchAll(
      db,
      sql: """
        select project_id, count(*) as total,
          coalesce(sum(created_at >= ? and created_at < ?), 0) as today
        from entries where project_id is not null group by project_id
        """, arguments: [start, end])
    var totals: [String: (total: Int, today: Int)] = [:]
    for row in counts {
      totals[row["project_id"]] = (row["total"], row["today"])
    }
    let projects = try fetchActiveProjects(db)
      .map { project in
        TodayDigest.ProjectActivity(
          project: project, addedToday: totals[project.id]?.today ?? 0,
          entryCount: totals[project.id]?.total ?? 0)
      }
      .sorted { ($0.addedToday, $0.entryCount) > ($1.addedToday, $1.entryCount) }

    let totalEntries =
      try Int.fetchOne(
        db,
        sql: """
          select count(*) from entries e left join projects p on p.id = e.project_id
          where p.archived_at is null
          """) ?? 0

    return TodayDigest(
      day: start, entries: entries,
      savedByClaude: entries.filter { $0.capture?.source == .claude }.count,
      notSure: order.compactMap { groups[$0] }, unsorted: unsorted, dueSoon: dueSoon,
      projects: projects, totalEntries: totalEntries,
      journal: try paragraphs(db, day: JournalDate.key(now, calendar: calendar)))
  }

  /// How many things wait for the user: "not sure" entries plus typed
  /// thoughts Claude hasn't sorted. The Inbox tab shows it as a badge.
  public static func waitingCount(_ db: Database) throws -> Int {
    try Int.fetchOne(
      db,
      sql: """
        select
          (select count(*) from entries where needs_review = 1)
          + (select count(*) from entries e join captures c on c.id = e.capture_id
             where c.source = 'typed' and c.status = 'unsorted')
        """) ?? 0
  }

  public func waitingCountUpdates() -> AsyncValueObservation<Int> {
    ValueObservation.tracking(Self.waitingCount).values(in: writer)
  }

  /// The digest, re-emitted after every change. Restart it when the day
  /// changes, since `now` is fixed for the observation.
  public func todayUpdates(now: Date = Date(), calendar: Calendar = .current)
    -> AsyncValueObservation<TodayDigest>
  {
    ValueObservation
      .tracking { db in try Self.today(db, now: now, calendar: calendar) }
      .values(in: writer)
  }
}
