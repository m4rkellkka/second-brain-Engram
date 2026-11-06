import CoreGraphics
import Foundation
import Testing

@testable import EngramKit

@Suite struct GraphFilterTests {
  let zone = TimeZone(identifier: "Europe/Istanbul") ?? .current
  var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
  }

  func local(_ day: Int, _ hour: Int = 12) -> Date {
    calendar.date(
      from: DateComponents(timeZone: zone, year: 2026, month: 11, day: day, hour: hour))
      ?? Date()
  }

  func node(
    _ id: String, _ project: String?, _ kind: EntryKind = .note, day: Int = 6,
    journal: Bool = false
  ) -> GraphSnapshot.Node {
    .init(
      id: id, projectID: project, kind: kind, content: id, createdAt: local(day),
      journalDay: journal ? "2026-11-0\(day)" : nil)
  }

  var graph: GraphSnapshot {
    GraphSnapshot(
      projects: [],
      nodes: [
        node("a", "p1", .task), node("b", "p2", .idea, day: 1), node("c", nil),
        node("d", "p1", .link, day: 5), node("j", nil, day: 4, journal: true),
      ], links: [])
  }

  @Test func showsEverythingByDefault() {
    let filter = GraphFilter()
    #expect(filter.visibility(for: graph, now: local(6), calendar: calendar).allSatisfy { $0 })
    #expect(!filter.isActive)
  }

  @Test func hidesProjectsKindsUnfiledAndJournal() {
    var filter = GraphFilter()
    filter.hiddenProjects = ["p1"]
    #expect(
      filter.visibility(for: graph, now: local(6), calendar: calendar)
        == [false, true, true, false, true])
    filter = GraphFilter()
    filter.kinds = [.idea, .note]
    filter.showUnfiled = false
    filter.showJournal = false
    #expect(
      filter.visibility(for: graph, now: local(6), calendar: calendar)
        == [false, true, false, false, false])
    #expect(filter.activeCount == 4)
  }

  @Test func periodCountsLocalDaysIncludingToday() {
    var filter = GraphFilter()
    filter.period = .week
    // Nov 6 back to Oct 31: the 1st, 4th, 5th and 6th are inside.
    #expect(filter.visibility(for: graph, now: local(6), calendar: calendar).allSatisfy { $0 })
    let old = GraphSnapshot(
      projects: [], nodes: [node("x", nil, day: 6), node("y", "p1", day: 1)], links: [])
    #expect(filter.visibility(for: old, now: local(8), calendar: calendar) == [true, false])
  }

  @Test func timelineFollowsSaveOrder() {
    let timeline = GraphTimeline(graph)
    #expect(timeline.order.map { graph.nodes[$0].id } == ["b", "j", "d", "a", "c"])
    #expect(timeline.rank[0] == 3)
    #expect(timeline.visibleCount(at: 0) == 0)
    #expect(timeline.visibleCount(at: 0.4) == 2)
    #expect(timeline.visibleCount(at: 1) == 5)
    #expect(timeline.visibleCount(at: 7) == 5)
    #expect(timeline.date(atCount: 2) == local(4))
    #expect(GraphTimeline.advance(15, speed: 4) == 2)
  }

  @Test func nearerLabelsWinAndOthersMoveOrHide() {
    let box = CGRect(x: 100, y: 100, width: 80, height: 22)
    let shifts = LabelPlacer.place([
      .init(id: "far", rect: box, depth: 9),
      .init(id: "near", rect: box, depth: 1),
      .init(id: "alone", rect: box.offsetBy(dx: 400, dy: 0), depth: 5),
    ])
    #expect(shifts["near"] == 0)
    #expect(shifts["alone"] == 0)
    #expect(shifts["far"] == -26)

    let crowd = (0..<8).map { LabelPlacer.Candidate(id: "l\($0)", rect: box, depth: Float($0)) }
    #expect(LabelPlacer.place(crowd).count == 5)
  }

  @Test func searchMatchesEntriesAndJournalDays() throws {
    let db = try AppDatabase.inMemory()
    let entry = try db.saveTypedThought("Шейдеры для графа", now: local(5))
    try db.saveTypedThought("Купить хлеб", now: local(5))
    _ = try db.writeJournalFromClaude(
      .init(text: "Весь вечер писал шейдеры."), now: local(5, 22), calendar: calendar)
    let matches = try db.writer.read { try AppDatabase.graphMatches($0, query: "шейдер") }
    #expect(matches == [entry.id, AppDatabase.journalNodeID("2026-11-05")])
  }
}
