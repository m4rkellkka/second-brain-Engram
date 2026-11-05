import AppKit
import EngramKit
import RealityKit
import SwiftUI
import simd

/// The Brain scene: builds entities from the graph, turns it, and maps
/// screen points back to nodes for hover and click.
@MainActor
final class GraphScene {
  let root = Entity()
  let camera = Entity()
  static let fieldOfView: Float = 50

  private(set) var snapshot = GraphSnapshot.empty
  private(set) var layout = GraphLayout(nodePositions: [], hubs: [:], radius: 1)
  private var yaw: Float = 0
  private var pitch: Float = 0.3
  private var distance: Float = 30
  private var lastInteraction = Date.distantPast
  private(set) var framesPerSecond: Double = 0
  /// Debug: hold the graph still (for checking hover alignment).
  var autoRotate = true

  static let nodeRadius: Float = 0.16
  static let hubRadius: Float = 0.5

  init() {
    camera.components.set(
      PerspectiveCameraComponent(near: 0.05, far: 2_000, fieldOfViewInDegrees: Self.fieldOfView))
    apply()
  }

  // MARK: Building

  func show(_ graph: GraphSnapshot) {
    guard graph != snapshot else { return }
    let isFirst = snapshot.nodes.isEmpty
    snapshot = graph
    layout = GraphLayout.compute(graph)
    if isFirst { distance = fitDistance() }
    rebuild()
  }

  private func rebuild() {
    for child in Array(root.children) { child.removeFromParent() }
    let positions = layout.nodePositions
    var groups: [String?: [Int]] = [:]
    for (i, node) in snapshot.nodes.enumerated() { groups[node.projectID, default: []].append(i) }

    for (projectID, indexes) in groups {
      let project = projectID.flatMap { id in snapshot.projects.first { $0.id == id } }
      let color = project.map { NSColor(Color(hexString: $0.color)) } ?? NSColor(Theme.textSubtle)
      add(try? GraphMesh.spheres(at: indexes.map { positions[$0] }, radius: Self.nodeRadius), color)
      if let projectID, let hub = layout.hubs[projectID] {
        add(try? GraphMesh.spheres(at: [hub], radius: Self.hubRadius), color)
        add(try? GraphMesh.spheres(at: [hub], radius: Self.hubRadius * 2.4), color, opacity: 0.12)
        let spokes = indexes.map { (hub, positions[$0]) }
        add(try? GraphMesh.lines(spokes, width: 0.012), color, opacity: 0.16)
      }
    }
    // Links inside a project are brighter than links across projects.
    let inside = snapshot.links.filter {
      snapshot.nodes[$0.source].projectID == snapshot.nodes[$0.target].projectID
    }
    let across = snapshot.links.filter {
      snapshot.nodes[$0.source].projectID != snapshot.nodes[$0.target].projectID
    }
    add(
      try? GraphMesh.lines(
        inside.map { (positions[$0.source], positions[$0.target]) }, width: 0.016),
      NSColor(Theme.accent), opacity: 0.3)
    add(
      try? GraphMesh.lines(
        across.map { (positions[$0.source], positions[$0.target]) }, width: 0.012),
      NSColor(Theme.accent), opacity: 0.09)
  }

  private func add(_ mesh: MeshResource?, _ color: NSColor, opacity: Float = 1) {
    guard let mesh else { return }
    root.addChild(ModelEntity(mesh: mesh, materials: [GraphMesh.material(color, opacity: opacity)]))
  }

  // MARK: Motion

  /// Called every frame. Turns slowly unless the user touched it recently.
  func tick(_ delta: Double) {
    if delta > 0 { framesPerSecond = framesPerSecond * 0.9 + (1 / delta) * 0.1 }
    if autoRotate, Date().timeIntervalSince(lastInteraction) > 3 { yaw += Float(delta) * 0.07 }
    apply()
  }

  func rotate(by translation: CGSize) {
    lastInteraction = Date()
    yaw += Float(translation.width) * 0.006
    pitch = min(max(pitch + Float(translation.height) * 0.006, -1.4), 1.4)
    apply()
  }

  func zoom(by factor: Float) {
    lastInteraction = Date()
    let fit = fitDistance()
    distance = min(max(distance * factor, fit * 0.15), fit * 3)
    apply()
  }

  private func apply() {
    root.orientation =
      simd_quatf(angle: pitch, axis: [1, 0, 0]) * simd_quatf(angle: yaw, axis: [0, 1, 0])
    camera.position = [0, 0, distance]
  }

  private func fitDistance() -> Float {
    layout.radius / tan(Self.fieldOfView * .pi / 360) * 1.15
  }

  // MARK: Picking

  /// Where a world point lands in a view of `size`, and how far it is.
  func project(_ point: SIMD3<Float>, in size: CGSize) -> (CGPoint, Float)? {
    let world = root.orientation.act(point)
    let depth = distance - world.z
    guard depth > 0.05, size.width > 0, size.height > 0 else { return nil }
    let scale = tan(Self.fieldOfView * .pi / 360) * depth
    let aspect = Float(size.width / size.height)
    let x = world.x / (scale * aspect)
    let y = world.y / scale
    return (
      CGPoint(x: CGFloat((x + 1) / 2) * size.width, y: CGFloat((1 - y) / 2) * size.height), depth
    )
  }

  /// The node nearest to `point` within a few points, preferring the front one.
  func node(at point: CGPoint, in size: CGSize) -> Int? {
    var best: (index: Int, score: CGFloat)?
    for (i, position) in layout.nodePositions.enumerated() {
      guard let (screen, depth) = project(position, in: size) else { continue }
      let gap = hypot(screen.x - point.x, screen.y - point.y)
      guard gap < 10 else { continue }
      let score = gap + CGFloat(depth) * 0.05
      if let current = best, current.score <= score { continue }
      best = (i, score)
    }
    return best?.index
  }

  func project(for node: Int) -> Project? {
    guard let id = snapshot.nodes[node].projectID else { return nil }
    return snapshot.projects.first { $0.id == id }
  }
}
