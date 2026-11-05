import Foundation
import GRDB
import Testing
import simd

@testable import EngramKit

@Suite struct GraphTests {
  func seeded() throws -> AppDatabase {
    let db = try AppDatabase.inMemory()
    for name in ["Engram", "Tamam", "Old"] { _ = try db.createProject(named: name) }
    _ = try db.saveFromClaude(
      SaveRequest(
        summary: "Graph.",
        entries: [
          EntryInput(
            kind: "note", content: "A", projectSlug: "engram", confidence: 1, keywords: ["x", "y"]),
          EntryInput(
            kind: "note", content: "B", projectSlug: "engram", confidence: 1, keywords: ["x", "y"]),
          EntryInput(kind: "idea", content: "C", projectSlug: "tamam", confidence: 1),
          EntryInput(kind: "task", content: "D", confidence: 1),
          EntryInput(
            kind: "note", content: "Hidden", projectSlug: "old", confidence: 1,
            keywords: ["x", "y"]),
        ]))
    let old = try #require(
      try db.writer.read { try Project.filter(Column("slug") == "old").fetchOne($0) })
    try db.setArchived(true, projectID: old.id)
    return db
  }

  @Test func snapshotSkipsArchivedProjectsAndMapsLinks() throws {
    let db = try seeded()
    let graph = try db.writer.read(AppDatabase.graph)
    #expect(graph.nodes.map(\.content) == ["A", "B", "C", "D"])
    #expect(graph.projects.map(\.name) == ["Engram", "Tamam"])
    // The link to the archived entry is dropped with it.
    #expect(graph.links.count == 1)
    let link = try #require(graph.links.first)
    #expect(
      Set([graph.nodes[link.source].content, graph.nodes[link.target].content]) == ["A", "B"])
  }

  @Test func layoutIsDeterministicAndFinite() throws {
    let graph = try seeded().writer.read(AppDatabase.graph)
    let first = GraphLayout.compute(graph)
    let second = GraphLayout.compute(graph)
    #expect(first.nodePositions == second.nodePositions)
    #expect(first.nodePositions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
    #expect(first.hubs.count == 2)
    #expect(first.nodePositions.allSatisfy { simd_length($0) <= first.radius })
  }

  @Test func projectsFormSeparateClusters() {
    // 200 entries in each of 6 projects, no links.
    let projects = (0..<6).map { i in
      Project(
        id: "p\(i)", name: "P\(i)", slug: "p\(i)", color: "#B79CFF", status: nil, summary: nil,
        summarySource: .ai, statusSource: .ai, contextUpdatedAt: nil, archivedAt: nil,
        createdAt: Date())
    }
    let nodes = (0..<1_200).map { i in
      GraphSnapshot.Node(id: "e\(i)", projectID: "p\(i % 6)", kind: .note, content: "")
    }
    let graph = GraphSnapshot(projects: projects, nodes: nodes, links: [])
    let layout = GraphLayout.compute(graph)

    // Every entry is closer to its own hub than to any other hub.
    for (i, node) in nodes.enumerated() {
      let position = layout.nodePositions[i]
      let own = simd_distance(position, layout.hubs[node.projectID ?? ""] ?? .zero)
      for (id, hub) in layout.hubs where id != node.projectID {
        #expect(own < simd_distance(position, hub))
      }
    }
  }

  @Test func clustersStayRoundWithChainedLinks() {
    // Links between entries saved one after another used to squash a
    // cluster into a vertical line.
    let project = Project(
      id: "p", name: "P", slug: "p", color: "#B79CFF", status: nil, summary: nil,
      summarySource: .ai, statusSource: .ai, contextUpdatedAt: nil, archivedAt: nil,
      createdAt: Date())
    let nodes = (0..<300).map {
      GraphSnapshot.Node(id: "e\($0)", projectID: "p", kind: .note, content: "")
    }
    let links = (0..<299).map { GraphSnapshot.Link(source: $0, target: $0 + 1, weight: 1) }
    let layout = GraphLayout.compute(GraphSnapshot(projects: [project], nodes: nodes, links: links))
    let spread = { (axis: Int) -> Float in
      let values = layout.nodePositions.map { $0[axis] }
      return (values.max() ?? 0) - (values.min() ?? 0)
    }
    #expect(spread(0) > spread(1) * 0.7)
    #expect(spread(2) > spread(1) * 0.7)
  }

  @Test func emptyGraph() {
    let layout = GraphLayout.compute(.empty)
    #expect(layout.nodePositions.isEmpty)
    #expect(layout.radius > 0)
  }
}
