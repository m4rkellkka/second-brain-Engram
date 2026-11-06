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
    /// How far above `point` the label sits so it clears the hub's glow.
    var lift: CGFloat
    var opacity: Double
  }

  var items: [Label] = []
}

/// Draws the Brain graph with Metal and owns everything that moves: the
/// orbit camera, hover and focus highlights, flashes for new entries, the
/// small pulses that run along links, and the glide of dots to their new
/// places when the data changes.
@MainActor
final class GraphRenderer: NSObject, MTKViewDelegate {
  typealias Sprite = GraphShaders.Sprite
  typealias Line = GraphShaders.Line

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
  private(set) var camera = GraphCamera()
  /// The project the camera is focused on, if any.
  private(set) var focusedProject: String?
  var hoveredNode: Int?
  var hoveredProject: String?
  var selectedNode: Int?
  private(set) var framesPerSecond: Double = 0

  // MARK: Metal

  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let spritePipeline: MTLRenderPipelineState
  private let linePipeline: MTLRenderPipelineState
  private static let framesInFlight = 3
  private let inFlight = DispatchSemaphore(value: framesInFlight)
  private var spriteBuffers = BufferRing(count: framesInFlight)
  private var lineBuffers = BufferRing(count: framesInFlight)

  // MARK: Derived data

  /// Where everything should end up (from `GraphLayout`).
  private var layout = GraphLayout(nodePositions: [], hubs: [:], radius: 1)
  /// Where everything is drawn this frame; glides toward `layout`.
  private var nodePositions: [SIMD3<Float>] = []
  private var hubPositions: [String: SIMD3<Float>] = [:]
  private var settling = false
  private var indexByID: [String: Int] = [:]
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
  private var backingScale: Float = 2

  static let unfiledColor = SIMD3<Float>(0.56, 0.56, 0.6)
  /// Journal days: the pale text color, so they read apart from projects.
  static let journalColor = SIMD3<Float>(0xE8, 0xEC, 0xF8) / 255
  static let accent = SIMD3<Float>(0x67, 0xE8, 0xF9) / 255
  /// Hub core and halo radii in world units.
  private static let hubRadius: Float = 0.42
  private static let haloRadius: Float = 1.4

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
    let isFirst = snapshot.nodes.isEmpty
    let previous = Dictionary(
      zip(snapshot.nodes.map(\.id), nodePositions), uniquingKeysWith: { first, _ in first })
    snapshot = graph
    layout = GraphLayout.compute(graph)
    colors = Dictionary(
      uniqueKeysWithValues: graph.projects.map { ($0.id, Self.rgb($0.color)) })
    indexByID = Dictionary(
      graph.nodes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })

    // Known dots start where they are now; new ones fly out of their hub.
    if isFirst {
      nodePositions = layout.nodePositions
      hubPositions = layout.hubs
    } else {
      let hubsNow = hubPositions
      hubPositions = Dictionary(
        uniqueKeysWithValues: layout.hubs.map { ($0.key, hubsNow[$0.key] ?? $0.value) })
      nodePositions = graph.nodes.enumerated().map { i, node in
        previous[node.id]
          ?? node.projectID.flatMap { hubPositions[$0] }
          ?? layout.nodePositions[i]
      }
      settling = true
    }

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
    // Pulses point at links by index, which may now mean other links.
    pulses.removeAll()

    if !isFirst {
      for node in graph.nodes where previous[node.id] == nil { flashes[node.id] = clock }
    }
    if stars.isEmpty { stars = Self.makeStars() }
    if let focusedProject, layout.hubs[focusedProject] == nil {
      focus(nil)
    } else {
      // Re-aim at the (possibly moved) hub, or refit the whole graph.
      focus(focusedProject)
    }
    if isFirst { camera.distance = desiredDistance * 1.25 }
  }

  /// The index of the entry with this id in the current snapshot.
  func index(of id: String) -> Int? { indexByID[id] }

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
    let hubIDs = Array(hubPositions.keys)
    let hubs = hubIDs.compactMap { hubPositions[$0] }
    // A hub is as easy to hit as it looks big, but never smaller than 16 pt.
    let hubReach =
      hubs.compactMap { camera.project($0, size: viewSize) }
      .map { camera.screenRadius(of: Self.hubRadius, atDepth: $0.1, height: viewSize.y) }
      .max() ?? 0
    if let hub = camera.nearest(
      to: location, among: hubs, size: viewSize, radius: max(16, min(hubReach, 40)))
    {
      return .hub(hubIDs[hub])
    }
    return camera.nearest(to: location, among: nodePositions, size: viewSize, radius: 9)
      .map(Hit.node)
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
    backingScale = Float(view.window?.backingScaleFactor ?? 2)
    updateLabels()
    var uniforms = Uniforms(
      viewProjection: camera.viewProjection(aspect: Float(size.width / max(size.height, 1))),
      viewport: [Float(size.width), Float(size.height), Float(clock), 5 * backingScale],
      fog: fogRange())

    let lines = makeLines()
    let sprites = makeSprites()
    if let buffer = lineBuffers.next(holding: lines, device: device) {
      encoder.setRenderPipelineState(linePipeline)
      encoder.setVertexBuffer(buffer, offset: 0, index: 0)
      encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      encoder.drawPrimitives(
        type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: lines.count)
    }
    if let buffer = spriteBuffers.next(holding: sprites, device: device) {
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

    // Dots and hubs glide to their new places in about half a second.
    if settling {
      let glide = 1 - exp(-dt * 7)
      var largest: Float = 0
      for i in nodePositions.indices {
        let gap = layout.nodePositions[i] - nodePositions[i]
        nodePositions[i] += gap * glide
        largest = max(largest, simd_length_squared(gap))
      }
      for (id, target) in layout.hubs {
        let current = hubPositions[id] ?? target
        hubPositions[id] = current + (target - current) * glide
        largest = max(largest, simd_length_squared(target - current))
      }
      if largest < 1e-6 {
        nodePositions = layout.nodePositions
        hubPositions = layout.hubs
        settling = false
      }
    }

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
  /// boosted for the hovered node and its neighbours or the hovered project.
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
    } else if let hoveredProject {
      for i in weights.indices {
        weights[i] = snapshot.nodes[i].projectID == hoveredProject ? 1.6 : weights[i] * 0.45
      }
    }
    return weights
  }

  private func hubDim(_ projectID: String) -> Float {
    if hoveredProject == projectID { return 1.3 }
    return focusedProject == nil || focusedProject == projectID ? 1 : 0.25
  }

  private func makeSprites() -> [Sprite] {
    let weights = emphasis()
    var sprites = stars
    sprites.reserveCapacity(
      stars.count + snapshot.nodes.count + 2 * hubPositions.count + pulses.count)
    for (i, node) in snapshot.nodes.enumerated() {
      let color =
        node.isJournal
        ? Self.journalColor : node.projectID.flatMap { colors[$0] } ?? Self.unfiledColor
      var glow = baseGlow[i] * weights[i]
      var size = baseSize[i] * (weights[i] > 1.5 ? 1.35 : 1)
      if let flash = flashes[node.id] {
        let t = Float((clock - flash) / 2.5)
        glow += (1 - t) * 2.5
        size *= 1 + (1 - t) * 1.5
      }
      sprites.append(Sprite(position: SIMD4(nodePositions[i], size), color: SIMD4(color, glow)))
    }
    // Hubs are bigger than any dot, so they get their own, larger caps.
    for (projectID, hub) in hubPositions {
      let color = colors[projectID] ?? Self.unfiledColor
      let dim = hubDim(projectID)
      let breathe = 0.9 + 0.1 * Float(sin(clock * 1.3 + Double(hub.x)))
      sprites.append(
        Sprite(
          position: SIMD4(hub, Self.haloRadius), color: SIMD4(color, 0.16 * dim),
          maxPixels: 90 * backingScale))
      sprites.append(
        Sprite(
          position: SIMD4(hub, Self.hubRadius), color: SIMD4(color, 1.4 * dim * breathe),
          maxPixels: 16 * backingScale))
    }
    for pulse in pulses {
      let link = snapshot.links[pulse.link]
      var t = Float((clock - pulse.start) / pulse.duration)
      if pulse.reversed { t = 1 - t }
      let a = nodePositions[link.source], b = nodePositions[link.target]
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

  private func makeLines() -> [Line] {
    let scale = backingScale
    let weights = emphasis()
    let active = hoveredNode ?? selectedNode
    let lit = Set(active.map { nodeLinks[$0] } ?? [])
    var lines: [Line] = []
    lines.reserveCapacity(snapshot.nodes.count + snapshot.links.count)
    // Spokes from each entry to its project's hub, faint.
    for (i, node) in snapshot.nodes.enumerated() {
      guard let projectID = node.projectID, let hub = hubPositions[projectID] else { continue }
      let color = colors[projectID] ?? Self.unfiledColor
      lines.append(
        Line(
          a: SIMD4(hub, 1 * scale), b: SIMD4(nodePositions[i], 0),
          color: SIMD4(color, 0.05 * weights[i])))
    }
    // Keyword links: project color inside a project, white dashes across.
    for (i, link) in snapshot.links.enumerated() {
      let from = snapshot.nodes[link.source], to = snapshot.nodes[link.target]
      // A journal day's links go across projects, like cross-project links.
      let inside = from.projectID == to.projectID && !from.isJournal && !to.isJournal
      let color =
        inside ? (from.projectID.flatMap { colors[$0] } ?? Self.unfiledColor) : SIMD3(1, 1, 1)
      let weight = min(weights[link.source], weights[link.target])
      var alpha = (inside ? 0.22 : 0.1) * Float(0.6 + 0.4 * link.weight) * min(weight, 1)
      if lit.contains(i) { alpha = 0.75 }
      lines.append(
        Line(
          a: SIMD4(nodePositions[link.source], (lit.contains(i) ? 1.6 : 1) * scale),
          b: SIMD4(nodePositions[link.target], inside ? 0 : 1),
          color: SIMD4(color, alpha)))
    }
    return lines
  }

  private func updateLabels() {
    let size = SIMD2(Float(viewSize.width), Float(viewSize.height))
    var items: [GraphLabels.Label] = []
    for (projectID, hub) in hubPositions {
      guard let (point, depth) = camera.project(hub, size: size) else { continue }
      // Sit above the hub's glow (about three core radii), whatever its size.
      let core = min(camera.screenRadius(of: Self.hubRadius, atDepth: depth, height: size.y), 16)
      let dim = focusedProject == nil || focusedProject == projectID
      // Far labels fade with the fog, but stay readable.
      let opacity = max(Double(fog(depth)), 0.55) * (dim ? 1 : 0.35)
      // Rounded so tiny camera moves don't redraw the labels every frame.
      items.append(
        .init(
          id: projectID,
          point: CGPoint(x: CGFloat(point.x.rounded()), y: CGFloat(point.y.rounded())),
          lift: CGFloat((core * 3 + 14).rounded()), opacity: (opacity * 50).rounded() / 50))
    }
    items.sort { $0.id < $1.id }
    if items != labels.items { labels.items = items }
  }

  // MARK: Helpers

  private func fogRange() -> SIMD4<Float> {
    let reach = focusedProject == nil ? layout.radius : max(layout.radius * 0.5, 4)
    // w: the projection's y scale, which the sprite shader sizes dots with.
    return [
      max(camera.distance - reach, 0.1), camera.distance + reach, 0.16,
      1 / tan(camera.fieldOfView / 2),
    ]
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

/// A few reusable GPU buffers, one per frame in flight, so drawing doesn't
/// allocate new ones every frame. A buffer only grows when it runs out.
struct BufferRing {
  private var buffers: [MTLBuffer?]
  private var current = 0

  init(count: Int) { buffers = Array(repeating: nil, count: count) }

  mutating func next<T>(holding items: [T], device: MTLDevice) -> MTLBuffer? {
    guard !items.isEmpty else { return nil }
    current = (current + 1) % buffers.count
    let length = MemoryLayout<T>.stride * items.count
    if (buffers[current]?.length ?? 0) < length {
      buffers[current] = device.makeBuffer(
        length: length + length / 2, options: .storageModeShared)
    }
    guard let buffer = buffers[current] else { return nil }
    items.withUnsafeBytes { bytes in
      if let base = bytes.baseAddress {
        buffer.contents().copyMemory(from: base, byteCount: length)
      }
    }
    return buffer
  }
}
