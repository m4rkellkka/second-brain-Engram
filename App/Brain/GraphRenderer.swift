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

/// The timeline under the graph: how far it has played and whether it plays.
/// The renderer advances it every frame; the bar only reads and scrubs it.
@Observable
@MainActor
final class TimelineState {
  /// 0 = nothing yet, 1 = everything (the normal view).
  var progress: Double = 1
  var playing = false
  var speed: Double = 1
  /// When the newest visible node was saved, for the label under the bar.
  var date: Date?
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
  /// Nodes the timeline just showed: a short, soft flash, since hundreds
  /// appear per second at 16× and full flashes would white out clusters.
  private var appearing: [Int: Double] = [:]
  private var pulses: [Pulse] = []
  private var nextPulse: Double = 0

  // MARK: What is drawn (filters, search, timeline); never moves anything

  /// The focus id for the cloud of unfiled entries.
  static let inboxID = "inbox"
  private var filterFlags: [Bool] = []
  private var matches: Set<String>?
  private(set) var timeline = GraphTimeline(.empty)
  private var timelineCount: Int?
  /// Per node: 0 hidden, dim for a search miss, 1 shown.
  private var alpha: [Float] = []
  private var drawnHubs: Set<String> = []
  /// Centre and reach of the Inbox nebula, if any unfiled entry is shown.
  private(set) var inboxCenter: SIMD3<Float>?
  private var inboxReach: Float = 1
  /// Links inside one project: the only ones that pulse and show at rest.
  private var insideLinks: [Int] = []
  let timelineState = TimelineState()

  // MARK: Motion

  private var desiredTarget: SIMD3<Float> = .zero
  private var desiredDistance: Float = 30
  private var lastInteraction = Date.distantPast
  private var lastFrame: CFTimeInterval = CACurrentMediaTime()
  private var clock: Double = 0
  private var lastDelta: Double = 0
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
        // Colors add up (glow), but the frame's alpha stays 1. Otherwise
        // bright pixels end up with more color than alpha, and wherever the
        // window composites a label over the graph they showed as light
        // rectangles.
        attachment?.sourceAlphaBlendFactor = .zero
        attachment?.destinationAlphaBlendFactor = .one
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
    appearing.removeAll()
    insideLinks = graph.links.indices.filter { isInside(graph.links[$0], in: graph) }
    timeline = GraphTimeline(graph)
    filterFlags = Array(repeating: true, count: graph.nodes.count)
    timelineCount =
      timelineState.progress >= 1 ? nil : timeline.visibleCount(at: timelineState.progress)
    refreshVisibility()

    if !isFirst {
      for node in graph.nodes where previous[node.id] == nil { flashes[node.id] = clock }
    }
    if stars.isEmpty { stars = Self.makeStars() }
    if let focusedProject, layout.hubs[focusedProject] == nil,
      !(focusedProject == Self.inboxID && inboxCenter != nil)
    {
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
    if projectID == Self.inboxID, let inboxCenter {
      desiredTarget = inboxCenter
      desiredDistance = fitDistance(inboxReach + 1.5)
    } else if let projectID, let hub = layout.hubs[projectID] {
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
    let hubIDs = hubPositions.keys.filter { drawnHubs.contains($0) }
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
    // Hidden nodes can't be hovered or clicked.
    let shown = nodePositions.indices.filter { $0 < alpha.count && alpha[$0] > 0 }
    return camera.nearest(
      to: location, among: shown.map { nodePositions[$0] }, size: viewSize, radius: 9
    )
    .map { Hit.node(shown[$0]) }
  }

  // MARK: Filters, search and timeline

  /// Which nodes the filter keeps, one flag per node of the current graph.
  func setFilter(_ flags: [Bool]) {
    guard flags.count == snapshot.nodes.count, flags != filterFlags else { return }
    filterFlags = flags
    refreshVisibility()
  }

  /// Node ids that match the ⌘F search; nil shows everything at full light.
  func setSearch(_ ids: Set<String>?) {
    guard ids != matches else { return }
    matches = ids
    refreshVisibility()
  }

  func isDrawn(_ index: Int) -> Bool { index < alpha.count && alpha[index] > 0 }

  /// The project (or the Inbox) a node belongs to; nil for journal days.
  func group(of index: Int) -> String? {
    let node = snapshot.nodes[index]
    if node.isJournal { return nil }
    return node.projectID ?? Self.inboxID
  }

  /// Shown neighbours of a node, strongest link first.
  func drawnNeighbours(of index: Int) -> [Int] {
    guard index < nodeLinks.count else { return [] }
    return nodeLinks[index]
      .map { snapshot.links[$0] }
      .sorted { $0.weight > $1.weight }
      .map { $0.source == index ? $0.target : $0.source }
      .filter(isDrawn)
  }

  /// The most linked shown node, in `group` if given: where a keyboard walk starts.
  func walkStart(in group: String?) -> Int? {
    snapshot.nodes.indices
      .filter { isDrawn($0) && (group == nil || self.group(of: $0) == group) }
      .max { (neighbours[$0].count, -$0) < (neighbours[$1].count, -$1) }
  }

  /// Flies close to one node.
  func aim(at index: Int) {
    guard index < nodePositions.count else { return }
    lastInteraction = Date()
    desiredTarget = layout.nodePositions[index]
    desiredDistance = fitDistance(3.5)
  }

  private func isInside(_ link: GraphSnapshot.Link, in graph: GraphSnapshot) -> Bool {
    let a = graph.nodes[link.source], b = graph.nodes[link.target]
    return a.projectID == b.projectID && !a.isJournal && !b.isJournal
  }

  /// Applies the timeline position: nodes that appear flash and fly out
  /// of their hub, as when they were saved.
  private func applyTimeline() {
    let state = timelineState
    if state.playing {
      state.progress = min(
        state.progress + GraphTimeline.advance(lastDelta, speed: state.speed), 1)
      if state.progress >= 1 { state.playing = false }
    }
    let count = state.progress >= 1 ? nil : timeline.visibleCount(at: state.progress)
    guard count != timelineCount else { return }
    let before = timelineCount ?? timeline.count
    let after = count ?? timeline.count
    timelineCount = count
    // A few at a time glow and fly out of their hub; a big jump (a drag
    // along the bar) just appears.
    if after > before, after - before <= 40 {
      for rank in before..<after {
        let index = timeline.order[rank]
        let node = snapshot.nodes[index]
        appearing[index] = clock
        if let hub = node.projectID.flatMap({ hubPositions[$0] }) {
          nodePositions[index] = hub
          settling = true
        }
      }
    }
    refreshVisibility()
    let date = timeline.date(atCount: after)
    if state.date != date { state.date = date }
  }

  private func refreshVisibility() {
    let count = snapshot.nodes.count
    var values = [Float](repeating: 0, count: count)
    var hubs: Set<String> = []
    var inboxSum = SIMD3<Float>.zero
    var inboxMembers: [Int] = []
    for i in 0..<count {
      guard i < filterFlags.count ? filterFlags[i] : true else { continue }
      if let timelineCount, timeline.rank[i] >= timelineCount { continue }
      let node = snapshot.nodes[i]
      values[i] = matches.map { $0.contains(node.id) ? 1 : 0.08 } ?? 1
      if let project = node.projectID {
        hubs.insert(project)
      } else if !node.isJournal {
        inboxSum += layout.nodePositions[i]
        inboxMembers.append(i)
      }
    }
    alpha = values
    drawnHubs = hubs
    if inboxMembers.isEmpty {
      inboxCenter = nil
    } else {
      let center = inboxSum / Float(inboxMembers.count)
      inboxCenter = center
      inboxReach = max(
        inboxMembers.map { simd_distance(layout.nodePositions[$0], center) }.max() ?? 1, 1)
    }
  }

  // MARK: Frame

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  func draw(in view: MTKView) {
    let now = CACurrentMediaTime()
    let delta = min(now - lastFrame, 0.1)
    lastFrame = now
    clock += delta
    lastDelta = delta
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
    applyTimeline()
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
    if let link = insideLinks.randomElement(), clock >= nextPulse, pulses.count < 28,
      alpha[snapshot.links[link].source] >= 1, alpha[snapshot.links[link].target] >= 1
    {
      var rng = SystemRandomNumberGenerator()
      pulses.append(
        Pulse(
          link: link, start: clock,
          duration: Double.random(in: 0.9...1.6, using: &rng), reversed: Bool.random(using: &rng)))
      nextPulse = clock + Double.random(in: 0.05...0.25, using: &rng)
    }
    flashes = flashes.filter { clock - $0.value < 2.5 }
    if !appearing.isEmpty { appearing = appearing.filter { clock - $0.value < 0.8 } }
  }

  // MARK: Building instances

  /// How lit each node is right now: dimmed outside the focused project,
  /// boosted for the hovered node and its neighbours or the hovered project.
  private func emphasis() -> [Float] {
    var weights = [Float](repeating: 1, count: snapshot.nodes.count)
    if let focusedProject {
      for i in weights.indices where group(of: i) != focusedProject {
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
    if let inboxCenter {
      let dim: Float =
        hoveredProject == Self.inboxID
        ? 1.6 : focusedProject == nil || focusedProject == Self.inboxID ? 1 : 0.3
      sprites.append(
        Sprite(
          position: SIMD4(inboxCenter, inboxReach * 0.9 + 0.6),
          color: SIMD4(Self.unfiledColor, 0.1 * dim), maxPixels: 520 * backingScale,
          shape: .nebula))
    }
    for (i, node) in snapshot.nodes.enumerated() where alpha[i] > 0 {
      let color =
        node.isJournal
        ? Self.journalColor : node.projectID.flatMap { colors[$0] } ?? Self.unfiledColor
      let shape: GraphShaders.Shape = node.isJournal ? .star : node.kind == .task ? .ring : .dot
      var glow = baseGlow[i] * weights[i] * alpha[i]
      var size =
        baseSize[i] * (weights[i] > 1.5 ? 1.35 : 1)
        * (shape == .star ? 1.7 : shape == .ring ? 1.3 : 1)
      // Search matches stand out from the dimmed rest.
      if matches != nil, alpha[i] >= 1 {
        size *= 1.6
        glow *= 1.4
      }
      if let start = appearing[i] {
        let t = Float((clock - start) / 0.8)
        glow += (1 - t) * 0.7
      }
      if let flash = flashes[node.id] {
        let t = Float((clock - flash) / 2.5)
        glow += (1 - t) * 2.5
        size *= 1 + (1 - t) * 1.5
      }
      sprites.append(
        Sprite(position: SIMD4(nodePositions[i], size), color: SIMD4(color, glow), shape: shape))
    }
    // Hubs are bigger than any dot, so they get their own, larger caps.
    for (projectID, hub) in hubPositions where drawnHubs.contains(projectID) {
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
      guard alpha[link.source] >= 1, alpha[link.target] >= 1 else { continue }
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
    for (i, node) in snapshot.nodes.enumerated() where alpha[i] > 0 {
      guard let projectID = node.projectID, let hub = hubPositions[projectID] else { continue }
      let color = colors[projectID] ?? Self.unfiledColor
      lines.append(
        Line(
          a: SIMD4(hub, 1 * scale), b: SIMD4(nodePositions[i], 0),
          color: SIMD4(color, 0.05 * weights[i] * alpha[i])))
    }
    // Keyword links: project color inside a project, white dashes across.
    for (i, link) in snapshot.links.enumerated() {
      let shown = min(alpha[link.source], alpha[link.target])
      guard shown > 0 else { continue }
      let from = snapshot.nodes[link.source], to = snapshot.nodes[link.target]
      // A journal day's links go across projects, like cross-project links.
      let inside = from.projectID == to.projectID && !from.isJournal && !to.isJournal
      // Links across projects (and a journal day's) show only for the
      // hovered or selected node, or the focused project.
      if !inside, !lit.contains(i),
        focusedProject == nil
          || (group(of: link.source) != focusedProject && group(of: link.target) != focusedProject)
      {
        continue
      }
      let color =
        inside ? (from.projectID.flatMap { colors[$0] } ?? Self.unfiledColor) : SIMD3(1, 1, 1)
      let weight = min(weights[link.source], weights[link.target])
      var alpha = (inside ? 0.22 : 0.1) * Float(0.6 + 0.4 * link.weight) * min(weight, 1) * shown
      if lit.contains(i) { alpha = 0.75 * shown }
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
    let names = Dictionary(
      snapshot.projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    var anchors: [(id: String, position: SIMD3<Float>, radius: Float)] =
      hubPositions
      .filter { drawnHubs.contains($0.key) }
      .map { ($0.key, $0.value, Self.hubRadius) }
    if let inboxCenter { anchors.append((Self.inboxID, inboxCenter, 0.3)) }

    var items: [GraphLabels.Label] = []
    var candidates: [LabelPlacer.Candidate] = []
    for anchor in anchors {
      guard let (point, depth) = camera.project(anchor.position, size: size) else { continue }
      // Sit above the hub's glow (about three core radii), whatever its size.
      let core = min(camera.screenRadius(of: anchor.radius, atDepth: depth, height: size.y), 16)
      let dim = focusedProject == nil || focusedProject == anchor.id
      // Far labels fade with the fog, but stay readable.
      let opacity = max(Double(fog(depth)), 0.55) * (dim ? 1 : 0.35)
      let lift = CGFloat((core * 3 + 14).rounded())
      let center = CGPoint(x: CGFloat(point.x.rounded()), y: CGFloat(point.y.rounded()))
      // About the width the capsule takes: dot, padding and the name.
      let name = anchor.id == Self.inboxID ? "Inbox" : names[anchor.id] ?? ""
      let width = CGFloat(30 + 7 * name.count)
      candidates.append(
        .init(
          id: anchor.id,
          rect: CGRect(x: center.x - width / 2, y: center.y - lift - 11, width: width, height: 22),
          depth: depth))
      items.append(
        .init(id: anchor.id, point: center, lift: lift, opacity: (opacity * 50).rounded() / 50))
    }
    // Nearer labels win; covered ones step aside or hide.
    let shifts = LabelPlacer.place(candidates)
    items = items.compactMap { item in
      guard let shift = shifts[item.id] else { return nil }
      var item = item
      item.lift -= shift
      return item
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
