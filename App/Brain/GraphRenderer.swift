import AppKit
import EngramKit
import MetalKit
import Observation
import simd

/// Where the project labels go this frame; the only SwiftUI state the
/// renderer touches, so per-frame updates redraw just the label layer.
@Observable
@MainActor
final class GraphLabels {
  struct Label: Identifiable, Equatable {
    var id: String
    var point: CGPoint
    var opacity: Double
  }

  var items: [Label] = []
}

/// Draws the Brain graph with Metal and owns everything that moves: the
/// orbit camera, hover and focus highlights, flashes for new entries and
/// the small pulses that run along links.
@MainActor
final class GraphRenderer: NSObject, MTKViewDelegate {
  struct Sprite {
    var position: SIMD4<Float>  // xyz, radius
    var color: SIMD4<Float>  // rgb, intensity
  }

  struct Line {
    var a: SIMD4<Float>  // xyz, width px
    var b: SIMD4<Float>  // xyz, dashed
    var color: SIMD4<Float>
  }

  struct Uniforms {
    var viewProjection: simd_float4x4
    var viewport: SIMD4<Float>
    var fog: SIMD4<Float>
  }

  private struct Pulse {
    var link: Int
    var start: Double
    var duration: Double
    var reversed: Bool
  }

  // MARK: State read by the SwiftUI overlay

  private(set) var snapshot = GraphSnapshot.empty
  private(set) var layout = GraphLayout(nodePositions: [], hubs: [:], radius: 1)
  private(set) var camera = GraphCamera()
  /// The project the camera is focused on, if any.
  private(set) var focusedProject: String?
  var hoveredNode: Int?
  var selectedNode: Int?
  private(set) var framesPerSecond: Double = 0

  // MARK: Metal

  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let spritePipeline: MTLRenderPipelineState
  private let linePipeline: MTLRenderPipelineState
  private let inFlight = DispatchSemaphore(value: 3)

  // MARK: Derived data

  private var neighbours: [[Int]] = []
  private var nodeLinks: [[Int]] = []
  private var baseSize: [Float] = []
  private var baseGlow: [Float] = []
  private var colors: [String: SIMD3<Float>] = [:]
  private var stars: [Sprite] = []
  private var flashes: [String: Double] = [:]
  private var pulses: [Pulse] = []
  private var nextPulse: Double = 0

  // MARK: Motion

  private var desiredTarget: SIMD3<Float> = .zero
  private var desiredDistance: Float = 30
  private var lastInteraction = Date.distantPast
  private var lastFrame: CFTimeInterval = CACurrentMediaTime()
  private var clock: Double = 0
  var autoRotate = true
  let labels = GraphLabels()
  private var viewSize: CGSize = .zero

  static let unfiledColor = SIMD3<Float>(0.56, 0.56, 0.6)
  static let accent = SIMD3<Float>(0x8B, 0x9C, 0xFF) / 255

  init?(view: MTKView) {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
    else { return nil }
    self.device = device
    self.queue = queue
    do {
      let library = try device.makeLibrary(source: GraphShaders.source, options: nil)
      func pipeline(_ vertex: String, _ fragment: String) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.rasterSampleCount = view.sampleCount
        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = view.colorPixelFormat
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .add
        attachment?.alphaBlendOperation = .add
        attachment?.sourceRGBBlendFactor = .one
        attachment?.destinationRGBBlendFactor = .one
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
      }
      spritePipeline = try pipeline("spriteVertex", "spriteFragment")
      linePipeline = try pipeline("lineVertex", "lineFragment")
    } catch {
      return nil
    }
    super.init()
    view.device = device
    view.delegate = self
  }

  // MARK: Data

  func show(_ graph: GraphSnapshot) {
    guard graph != snapshot else { return }
    let previous = Set(snapshot.nodes.map(\.id))
    let isFirst = snapshot.nodes.isEmpty
    snapshot = graph
    layout = GraphLayout.compute(graph)
    colors = Dictionary(
      uniqueKeysWithValues: graph.projects.map { ($0.id, Self.rgb($0.color)) })

    neighbours = Array(repeating: [], count: graph.nodes.count)
    nodeLinks = Array(repeating: [], count: graph.nodes.count)
    for (i, link) in graph.links.enumerated() {
      neighbours[link.source].append(link.target)
      neighbours[link.target].append(link.source)
      nodeLinks[link.source].append(i)
      nodeLinks[link.target].append(i)
    }
    // Bigger with more links; newer entries a bit brighter, done tasks dimmer.
    let ranked = graph.nodes.indices.sorted {
      graph.nodes[$0].createdAt < graph.nodes[$1].createdAt
    }
    var recency = [Float](repeating: 1, count: graph.nodes.count)
    for (rank, index) in ranked.enumerated() {
      recency[index] = 0.7 + 0.3 * Float(rank + 1) / Float(max(ranked.count, 1))
    }
    baseSize = graph.nodes.indices.map { i in
      min(0.09 * (1 + 0.45 * Float(neighbours[i].count).squareRoot()), 0.26)
    }
    baseGlow = graph.nodes.indices.map { i in
      recency[i] * (graph.nodes[i].done ? 0.45 : 1)
    }

    if !isFirst {
      for node in graph.nodes where !previous.contains(node.id) { flashes[node.id] = clock }
    }
    if stars.isEmpty { stars = Self.makeStars() }
    if isFirst || focusedProject == nil {
      desiredTarget = .zero
      desiredDistance = fitDistance(layout.radius)
      if isFirst { camera.distance = desiredDistance * 1.25 }
    }
    if let focusedProject, layout.hubs[focusedProject] == nil { focus(nil) }
  }

  // MARK: Interaction

  func orbit(by translation: CGSize) {
    lastInteraction = Date()
    camera.yaw -= Float(translation.width) * 0.006
    camera.pitch = min(max(camera.pitch + Float(translation.height) * 0.006, -1.45), 1.45)
  }

  func zoom(by factor: Float) {
    lastInteraction = Date()
    let base = focusedProject == nil ? fitDistance(layout.radius) : desiredDistance
    desiredDistance = min(
      max(desiredDistance * factor, base * 0.12), fitDistance(layout.radius) * 3)
  }

  /// Flies to a project's cluster (or back to the whole graph with nil).
  func focus(_ projectID: String?) {
    focusedProject = projectID
    if let projectID, let hub = layout.hubs[projectID] {
      let members = snapshot.nodes.indices.filter { snapshot.nodes[$0].projectID == projectID }
      let reach = members.map { simd_distance(layout.nodePositions[$0], hub) }.max() ?? 2
      desiredTarget = hub
      desiredDistance = fitDistance(reach + 1.5)
    } else {
      desiredTarget = .zero
      desiredDistance = fitDistance(layout.radius)
    }
  }

  enum Hit: Equatable {
    case hub(String)
    case node(Int)
  }

  func hit(at point: CGPoint, size: CGSize) -> Hit? {
    let location = SIMD2(Float(point.x), Float(point.y))
    let viewSize = SIMD2(Float(size.width), Float(size.height))
    let hubIDs = Array(layout.hubs.keys)
    if let hub = camera.nearest(
      to: location, among: hubIDs.compactMap { layout.hubs[$0] }, size: viewSize, radius: 16)
    {
      return .hub(hubIDs[hub])
    }
    return camera.nearest(to: location, among: layout.nodePositions, size: viewSize, radius: 9)
      .map(Hit.node)
  }

  func screenPoint(of point: SIMD3<Float>, size: CGSize) -> (CGPoint, Float)? {
    camera.project(point, size: SIMD2(Float(size.width), Float(size.height)))
      .map { (CGPoint(x: CGFloat($0.0.x), y: CGFloat($0.0.y)), fog($0.1)) }
  }

  // MARK: Frame

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  func draw(in view: MTKView) {
    let now = CACurrentMediaTime()
    let delta = min(now - lastFrame, 0.1)
    lastFrame = now
    clock += delta
    if delta > 0 { framesPerSecond = framesPerSecond * 0.92 + (1 / delta) * 0.08 }
    step(delta)

    guard !snapshot.nodes.isEmpty, let pass = view.currentRenderPassDescriptor,
      let drawable = view.currentDrawable
    else { return }
    inFlight.wait()
    guard let commands = queue.makeCommandBuffer(),
      let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
    else {
      inFlight.signal()
      return
    }
    let size = view.drawableSize
    viewSize = view.bounds.size
    updateLabels()
    var uniforms = Uniforms(
      viewProjection: camera.viewProjection(aspect: Float(size.width / max(size.height, 1))),
      viewport: [
        Float(size.width), Float(size.height), Float(clock),
        5 * Float(view.window?.backingScaleFactor ?? 2),
      ],
      fog: fogRange())

    let lines = makeLines(scale: Float(view.window?.backingScaleFactor ?? 2))
    let sprites = makeSprites()
    if !lines.isEmpty,
      let buffer = device.makeBuffer(
        bytes: lines, length: MemoryLayout<Line>.stride * lines.count)
    {
      encoder.setRenderPipelineState(linePipeline)
      encoder.setVertexBuffer(buffer, offset: 0, index: 0)
      encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      encoder.drawPrimitives(
        type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: lines.count)
    }
    if !sprites.isEmpty,
      let buffer = device.makeBuffer(
        bytes: sprites, length: MemoryLayout<Sprite>.stride * sprites.count)
    {
      encoder.setRenderPipelineState(spritePipeline)
      encoder.setVertexBuffer(buffer, offset: 0, index: 0)
      encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      encoder.drawPrimitives(
        type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: sprites.count)
    }
    encoder.endEncoding()
    let semaphore = inFlight
    commands.addCompletedHandler { _ in semaphore.signal() }
    commands.present(drawable)
    commands.commit()
  }

  private func step(_ delta: Double) {
    let dt = Float(delta)
    if autoRotate, Date().timeIntervalSince(lastInteraction) > 3 { camera.yaw += dt * 0.06 }
    let ease = 1 - exp(-dt * 4)
    camera.target += (desiredTarget - camera.target) * ease
    camera.distance += (desiredDistance - camera.distance) * ease

    // Pulses: a few at a time, each runs along one link in about a second.
    pulses.removeAll { clock - $0.start > $0.duration }
    if !snapshot.links.isEmpty, clock >= nextPulse, pulses.count < 28 {
      var rng = SystemRandomNumberGenerator()
      pulses.append(
        Pulse(
          link: Int.random(in: 0..<snapshot.links.count, using: &rng), start: clock,
          duration: Double.random(in: 0.9...1.6, using: &rng), reversed: Bool.random(using: &rng)))
      nextPulse = clock + Double.random(in: 0.05...0.25, using: &rng)
    }
    flashes = flashes.filter { clock - $0.value < 2.5 }
  }

  // MARK: Building instances

  /// How lit each node is right now: dimmed outside the focused project,
  /// boosted for the hovered node and its neighbours.
  private func emphasis() -> [Float] {
    var weights = [Float](repeating: 1, count: snapshot.nodes.count)
    if let focusedProject {
      for i in weights.indices where snapshot.nodes[i].projectID != focusedProject {
        weights[i] = 0.18
      }
    }
    if let active = hoveredNode ?? selectedNode, active < weights.count {
      for i in weights.indices { weights[i] *= 0.45 }
      weights[active] = 2.2
      for n in neighbours[active] { weights[n] = max(weights[n], 1.6) }
    }
    return weights
  }

  private func makeSprites() -> [Sprite] {
    let weights = emphasis()
    var sprites = stars
    sprites.reserveCapacity(stars.count + snapshot.nodes.count + layout.hubs.count + pulses.count)
    for (i, node) in snapshot.nodes.enumerated() {
      let color = node.projectID.flatMap { colors[$0] } ?? Self.unfiledColor
      var glow = baseGlow[i] * weights[i]
      var size = baseSize[i] * (weights[i] > 1.5 ? 1.35 : 1)
      if let flash = flashes[node.id] {
        let t = Float((clock - flash) / 2.5)
        glow += (1 - t) * 2.5
        size *= 1 + (1 - t) * 1.5
      }
      sprites.append(
        Sprite(position: SIMD4(layout.nodePositions[i], size), color: SIMD4(color, glow)))
    }
    for (projectID, hub) in layout.hubs {
      let color = colors[projectID] ?? Self.unfiledColor
      let dim: Float = focusedProject == nil || focusedProject == projectID ? 1 : 0.25
      let breathe = 0.9 + 0.1 * Float(sin(clock * 1.3 + Double(hub.x)))
      sprites.append(Sprite(position: SIMD4(hub, 0.42), color: SIMD4(color, 1.4 * dim * breathe)))
      sprites.append(Sprite(position: SIMD4(hub, 1.4), color: SIMD4(color, 0.16 * dim)))
    }
    for pulse in pulses {
      let link = snapshot.links[pulse.link]
      var t = Float((clock - pulse.start) / pulse.duration)
      if pulse.reversed { t = 1 - t }
      let a = layout.nodePositions[link.source], b = layout.nodePositions[link.target]
      let color = snapshot.nodes[link.source].projectID.flatMap { colors[$0] } ?? Self.accent
      let fade = sin(Float.pi * Float((clock - pulse.start) / pulse.duration))
      let dim: Float =
        focusedProject == nil || snapshot.nodes[link.source].projectID == focusedProject ? 1 : 0.2
      sprites.append(
        Sprite(
          position: SIMD4(a + (b - a) * t, 0.07), color: SIMD4(color * 0.5 + 0.5, 1.6 * fade * dim))
      )
    }
    return sprites
  }

  private func makeLines(scale: Float) -> [Line] {
    let weights = emphasis()
    let active = hoveredNode ?? selectedNode
    let lit = Set(active.map { nodeLinks[$0] } ?? [])
    var lines: [Line] = []
    lines.reserveCapacity(snapshot.nodes.count + snapshot.links.count)
    // Spokes from each entry to its project's hub, faint.
    for (i, node) in snapshot.nodes.enumerated() {
      guard let projectID = node.projectID, let hub = layout.hubs[projectID] else { continue }
      let color = colors[projectID] ?? Self.unfiledColor
      lines.append(
        Line(
          a: SIMD4(hub, 1 * scale), b: SIMD4(layout.nodePositions[i], 0),
          color: SIMD4(color, 0.05 * weights[i])))
    }
    // Keyword links: project color inside a project, white dashes across.
    for (i, link) in snapshot.links.enumerated() {
      let from = snapshot.nodes[link.source], to = snapshot.nodes[link.target]
      let inside = from.projectID == to.projectID
      let color =
        inside ? (from.projectID.flatMap { colors[$0] } ?? Self.unfiledColor) : SIMD3(1, 1, 1)
      let weight = min(weights[link.source], weights[link.target])
      var alpha = (inside ? 0.22 : 0.1) * Float(0.6 + 0.4 * link.weight) * min(weight, 1)
      if lit.contains(i) { alpha = 0.75 }
      lines.append(
        Line(
          a: SIMD4(layout.nodePositions[link.source], (lit.contains(i) ? 1.6 : 1) * scale),
          b: SIMD4(layout.nodePositions[link.target], inside ? 0 : 1),
          color: SIMD4(color, alpha)))
    }
    return lines
  }

  private func updateLabels() {
    var items: [GraphLabels.Label] = []
    for (projectID, hub) in layout.hubs {
      guard let (point, fog) = screenPoint(of: hub, size: viewSize) else { continue }
      let dim = focusedProject == nil || focusedProject == projectID
      items.append(.init(id: projectID, point: point, opacity: Double(fog) * (dim ? 1 : 0.35)))
    }
    items.sort { $0.id < $1.id }
    if items != labels.items { labels.items = items }
  }

  // MARK: Helpers

  private func fogRange() -> SIMD4<Float> {
    let reach = focusedProject == nil ? layout.radius : max(layout.radius * 0.5, 4)
    return [max(camera.distance - reach, 0.1), camera.distance + reach, 0.16, 0]
  }

  private func fog(_ depth: Float) -> Float {
    let range = fogRange()
    return min(max(1 - (depth - range.x) / max(range.y - range.x, 0.001), range.z), 1)
  }

  private func fitDistance(_ radius: Float) -> Float {
    radius / tan(camera.fieldOfView / 2) * 1.1
  }

  /// A faint, fixed field of distant stars around the graph.
  private static func makeStars() -> [Sprite] {
    var stars: [Sprite] = []
    for i in 0..<420 {
      let y = 1 - 2 * (Float(i) + 0.5) / 420
      let r = (1 - y * y).squareRoot()
      let theta = Float(i) * 2.399_963
      let distance: Float = 160 + Float((i * 37) % 60)
      let point = SIMD3(cos(theta) * r, y, sin(theta) * r) * distance
      stars.append(Sprite(position: SIMD4(point, 0.18), color: SIMD4(0.75, 0.78, 1, 0.35)))
    }
    return stars
  }

  static func rgb(_ hex: String) -> SIMD3<Float> {
    let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return accent }
    return SIMD3(
      Float((value >> 16) & 0xFF), Float((value >> 8) & 0xFF), Float(value & 0xFF)) / 255
  }
}
