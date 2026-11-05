import Foundation
import GRDB
import Testing

@testable import EngramKit

@Suite struct ProjectNamingTests {
  @Test(arguments: [
    ("Engram", "engram"),
    ("Chess Coach", "chess-coach"),
    ("  Tally / v2!  ", "tally-v2"),
    ("Жизнь", "zhizn"),
    ("Мойка машины", "moyka-mashiny"),
    ("Ёлка", "elka"),
    ("Café Ölbaum", "cafe-olbaum"),
    ("Учёба 2026", "ucheba-2026"),
  ])
  func slugify(name: String, slug: String) {
    #expect(ProjectNaming.slugify(name) == slug)
  }

  @Test func slugFallsBackToProject() {
    #expect(ProjectNaming.slugify("🚀✨") == "project")
    #expect(ProjectNaming.slugify("---") == "project")
  }

  @Test func longSlugIsCutWithoutATrailingDash() {
    let slug = ProjectNaming.slugify(String(repeating: "a", count: 47) + " b")
    #expect(slug.count <= 48)
    #expect(!slug.hasSuffix("-"))
  }

  @Test func uniqueSlugAddsTheFirstFreeNumber() {
    #expect(ProjectNaming.uniqueSlug("life", taken: ["engram"]) == "life")
    #expect(ProjectNaming.uniqueSlug("life", taken: ["life", "life-2"]) == "life-3")
  }

  @Test func pickColor() {
    let colors = ProjectNaming.colors
    #expect(ProjectNaming.pickColor(used: []) == colors[0])
    #expect(ProjectNaming.pickColor(used: ["#b79cff", "#3FD0B6"]) == "#F2A65A")
    #expect(ProjectNaming.pickColor(used: colors + colors.prefix(3)) == colors[3])
  }

  @Test func nameIsValidated() throws {
    #expect(try ProjectNaming.validatedName("  Engram ") == "Engram")
    #expect(throws: EngramError.emptyProjectName) { try ProjectNaming.validatedName("  ") }
    #expect(throws: EngramError.projectNameTooLong(limit: 60)) {
      try ProjectNaming.validatedName(String(repeating: "x", count: 61))
    }
  }
}

@Suite struct ProjectStoreTests {
  @Test func createsWithSlugAndColor() throws {
    let db = try AppDatabase.inMemory()
    let project = try db.createProject(named: "Мойка машины")
    #expect(project.slug == "moyka-mashiny")
    #expect(project.color == ProjectNaming.colors[0])
    #expect(project.summarySource == .ai)
  }

  @Test func sameNameReturnsTheExistingProject() throws {
    let db = try AppDatabase.inMemory()
    let first = try db.createProject(named: "Engram")
    let second = try db.createProject(named: "engram ")
    #expect(first.id == second.id)
    let count = try db.writer.read { try Project.fetchCount($0) }
    #expect(count == 1)
  }

  @Test func clashingSlugGetsANumberAndNextColor() throws {
    let db = try AppDatabase.inMemory()
    _ = try db.createProject(named: "Life")
    let second = try db.createProject(named: "Life!")
    #expect(second.slug == "life-2")
    #expect(second.color == ProjectNaming.colors[1])
  }

  @Test func archivedProjectsAreHiddenAndNotReused() throws {
    let db = try AppDatabase.inMemory()
    var old = try db.createProject(named: "Engram")
    old.archivedAt = Date()
    try db.writer.write { [old] in try old.update($0) }

    let fresh = try db.createProject(named: "Engram")
    #expect(fresh.id != old.id)
    #expect(fresh.slug == "engram-2")

    let active = try db.writer.read { try AppDatabase.fetchActiveProjects($0) }
    #expect(active.map(\.id) == [fresh.id])
  }

  @Test func activeProjectsAreSortedByNameIgnoringCase() throws {
    let db = try AppDatabase.inMemory()
    for name in ["zeta", "Alpha", "beta"] { try db.createProject(named: name) }
    let names = try db.writer.read { try AppDatabase.fetchActiveProjects($0) }.map(\.name)
    #expect(names == ["Alpha", "beta", "zeta"])
  }
}
