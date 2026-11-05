import Foundation
import GRDB

/// What the Brain graph shows: entries of active projects (and unfiled
/// ones), their projects and the keyword links between them.
public struct GraphSnapshot: Hashable, Sendable {
  public struct Node: Hashable, Sendable, Identifiable {
    public var id: String
    public var projectID: String?
    public var kind: EntryKind
    public var content: String
    public var done: Bool = false
    public var createdAt: Date = .distantPast
  }

  public struct Link: Hashable, Sendable {
    public var source: Int
    public var target: Int
    public var weight: Double
  }

  public var projects: [Project]
  public var nodes: [Node]
  /// Indexes into `nodes`.
  public var links: [Link]

  public static let empty = GraphSnapshot(projects: [], nodes: [], links: [])
}

extension AppDatabase {
  public static func graph(_ db: Database) throws -> GraphSnapshot {
    let projects = try fetchActiveProjects(db)
    let active = Set(projects.map(\.id))
    let rows = try Row.fetchAll(
      db,
      sql: """
        select id, project_id, kind, substr(content, 1, 160) as content, done_at, created_at
        from entries
        order by created_at, rowid
        """)
    var nodes: [GraphSnapshot.Node] = []
    for row in rows {
      let projectID: String? = row["project_id"]
      // Entries of archived projects stay out of the graph.
      if let projectID, !active.contains(projectID) { continue }
      nodes.append(
        .init(
          id: row["id"], projectID: projectID,
          kind: EntryKind(rawValue: row["kind"]) ?? .note, content: row["content"],
          done: (row["done_at"] as String?) != nil, createdAt: row["created_at"]))
    }
    let index = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
    let links = try Row.fetchAll(db, sql: "select source_id, target_id, weight from entry_links")
      .compactMap { row -> GraphSnapshot.Link? in
        guard let s = index[row["source_id"] as String], let t = index[row["target_id"] as String]
        else { return nil }
        return .init(source: s, target: t, weight: row["weight"])
      }
    return GraphSnapshot(projects: projects, nodes: nodes, links: links)
  }

  public func graphUpdates() -> AsyncValueObservation<GraphSnapshot> {
    ValueObservation.tracking(Self.graph).values(in: writer)
  }
}
