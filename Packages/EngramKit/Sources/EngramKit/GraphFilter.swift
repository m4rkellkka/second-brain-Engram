import CoreGraphics
import Foundation
import GRDB

/// What the Brain shows. Filtering never moves anything: it only says which
/// nodes are drawn, so the layout stays as it is.
public struct GraphFilter: Hashable, Sendable {
  public enum Period: String, CaseIterable, Sendable, Identifiable {
    case all, week, month, quarter, year

    public var id: String { rawValue }

    public var title: String {
      switch self {
      case .all: "All time"
      case .week: "7 days"
      case .month: "30 days"
      case .quarter: "90 days"
      case .year: "A year"
      }
    }

    var days: Int? {
      switch self {
      case .all: nil
      case .week: 7
      case .month: 30
      case .quarter: 90
      case .year: 365
      }
    }
  }

  /// Projects whose entries are hidden.
  public var hiddenProjects: Set<String> = []
  /// Entries without a project (the Inbox nebula).
  public var showUnfiled = true
  public var kinds: Set<EntryKind> = Set(EntryKind.allCases)
  public var showJournal = true
  public var period: Period = .all

  public init() {}

  /// How many settings differ from "show everything", for the button badge.
  public var activeCount: Int {
    var count = hiddenProjects.count + (EntryKind.allCases.count - kinds.count)
    if !showUnfiled { count += 1 }
    if !showJournal { count += 1 }
    if period != .all { count += 1 }
    return count
  }

  public var isActive: Bool { activeCount > 0 }

  /// One flag per node of `graph`: drawn or not.
  public func visibility(
    for graph: GraphSnapshot, now: Date = Date(), calendar: Calendar = .current
  ) -> [Bool] {
    let since = period.days.flatMap {
      calendar.date(byAdding: .day, value: -$0 + 1, to: calendar.startOfDay(for: now))
    }
    return graph.nodes.map { node in
      if let since, node.createdAt < since { return false }
      if node.isJournal { return showJournal }
      guard kinds.contains(node.kind) else { return false }
      guard let project = node.projectID else { return showUnfiled }
      return !hiddenProjects.contains(project)
    }
  }
}

/// The order the graph grew in, for the timeline: nodes by the time they
/// were saved (journal days at the start of their day).
public struct GraphTimeline: Sendable, Equatable {
  /// Playing the whole history takes this long at 1×.
  public static let fullPlaySeconds: Double = 30

  /// Node indexes, oldest first.
  public let order: [Int]
  /// Each node's place in `order`.
  public let rank: [Int]
  private let dates: [Date]

  public init(_ graph: GraphSnapshot) {
    let order = graph.nodes.indices.sorted {
      (graph.nodes[$0].createdAt, $0) < (graph.nodes[$1].createdAt, $1)
    }
    var rank = [Int](repeating: 0, count: graph.nodes.count)
    for (place, index) in order.enumerated() { rank[index] = place }
    self.order = order
    self.rank = rank
    self.dates = order.map { graph.nodes[$0].createdAt }
  }

  public var count: Int { order.count }

  /// How many nodes have appeared at `progress` (0 = none, 1 = all).
  public func visibleCount(at progress: Double) -> Int {
    let clamped = min(max(progress, 0), 1)
    return min(Int((clamped * Double(count)).rounded(.down)), count)
  }

  /// When the newest node visible at `visibleCount` was saved.
  public func date(atCount visibleCount: Int) -> Date? {
    guard visibleCount > 0, !dates.isEmpty else { return dates.first }
    return dates[min(visibleCount, dates.count) - 1]
  }

  /// How far the timeline moves in `seconds` of playback at `speed`.
  public static func advance(_ seconds: Double, speed: Double) -> Double {
    seconds * speed / fullPlaySeconds
  }
}

/// Keeps labels from covering each other: nearer labels win, a farther one
/// moves up or down a step if that frees it, otherwise it hides.
public enum LabelPlacer {
  public struct Candidate: Sendable, Equatable {
    public var id: String
    /// Where the label would sit, in view points.
    public var rect: CGRect
    /// Distance from the camera; smaller is nearer.
    public var depth: Float

    public init(id: String, rect: CGRect, depth: Float) {
      self.id = id
      self.rect = rect
      self.depth = depth
    }
  }

  /// The vertical shift for each label that fits; hidden ones are missing.
  public static func place(_ candidates: [Candidate], gap: CGFloat = 4) -> [String: CGFloat] {
    var placed: [CGRect] = []
    var shifts: [String: CGFloat] = [:]
    for candidate in candidates.sorted(by: { ($0.depth, $0.id) < ($1.depth, $1.id) }) {
      let step = candidate.rect.height + gap
      for shift in [0, -step, step, -2 * step, 2 * step] {
        let rect = candidate.rect.offsetBy(dx: 0, dy: shift)
        if !placed.contains(where: { $0.insetBy(dx: -gap, dy: -gap).intersects(rect) }) {
          placed.append(rect)
          shifts[candidate.id] = shift
          break
        }
      }
    }
    return shifts
  }
}

extension AppDatabase {
  /// Graph node ids that match a search: entries through the entries index,
  /// journal days through the journal index.
  public static func graphMatches(_ db: Database, query: String) throws -> Set<String> {
    let entries = try search(db, query: query, limit: 5_000).map(\.entry.id)
    let days = try searchJournal(db, query: query, limit: 1_000).map { journalNodeID($0.day) }
    return Set(entries).union(days)
  }
}
