import Foundation
import simd

/// Places the graph in 3D: project hubs spread evenly on a sphere, each
/// project's entries in a ball around its hub, unfiled entries in the
/// middle, then linked entries pulled a little closer. Deterministic: the
/// same data always gives the same picture, so nothing jumps between launches.
///
/// Stable as data grows: an entry's spot in its ball comes from its own id,
/// and ball and ring sizes move in steps, so saving one more entry leaves
/// everything else where it was.
public struct GraphLayout: Sendable {
  public var nodePositions: [SIMD3<Float>]
  /// Hub position per project id.
  public var hubs: [String: SIMD3<Float>]
  /// Distance from the origin that contains everything.
  public var radius: Float

  public init(nodePositions: [SIMD3<Float>], hubs: [String: SIMD3<Float>], radius: Float) {
    self.nodePositions = nodePositions
    self.hubs = hubs
    self.radius = radius
  }

  public static func compute(_ graph: GraphSnapshot) -> GraphLayout {
    var members: [String?: [Int]] = [:]
    var journal: [Int] = []
    for (i, node) in graph.nodes.enumerated() {
      if node.isJournal {
        journal.append(i)
      } else {
        members[node.projectID, default: []].append(i)
      }
    }

    func clusterRadius(_ count: Int) -> Float {
      1.1 * Float(sizeStep(count)).squareRoot().squareRoot() * 1.4
    }
    let largest = members.values.map(\.count).max() ?? 1
    let projectIDs = graph.projects.map(\.id).filter { members[$0] != nil }
    let ring = max(6, 2.8 * clusterRadius(largest))

    var hubs: [String: SIMD3<Float>] = [:]
    for (i, id) in projectIDs.enumerated() {
      hubs[id] =
        projectIDs.count == 1 && members[nil] == nil
        ? .zero : fibonacciSphere(i, count: projectIDs.count) * ring
    }

    var positions = [SIMD3<Float>](repeating: .zero, count: graph.nodes.count)
    var restLength = [String?: Float]()
    for (projectID, members) in members {
      let center = projectID.flatMap { hubs[$0] } ?? .zero
      let r = clusterRadius(members.count)
      restLength[projectID] = r * 0.35
      for index in members {
        var rng = SeededRandom(graph.nodes[index].id)
        positions[index] = center + pointInBall(&rng) * r
      }
    }

    // Links act as springs with a rest length: they pull far-apart linked
    // entries closer but leave near ones alone, so clusters keep their shape.
    // Links across projects pull much less.
    for _ in 0..<24 {
      for link in graph.links {
        let a = link.source, b = link.target
        // Journal days sit on their own arc and pull on nothing.
        if graph.nodes[a].isJournal || graph.nodes[b].isJournal { continue }
        let same = graph.nodes[a].projectID == graph.nodes[b].projectID
        let delta = positions[b] - positions[a]
        let length = simd_length(delta)
        let rest = same ? restLength[graph.nodes[a].projectID] ?? 1 : 0
        guard length > rest, length > 0 else { continue }
        let pull = Float(link.weight) * (same ? 0.04 : 0.004)
        let step = delta / length * (length - rest) * pull
        positions[a] += step
        positions[b] -= step
      }
    }

    placeJournal(journal, of: graph, ring: ring, into: &positions)

    let radius = max(positions.map { simd_length($0) }.max() ?? 1, ring, 1) + 1
    return GraphLayout(nodePositions: positions, hubs: hubs, radius: radius)
  }

  /// Journal days on a slow spiral above the clusters, one turn a month,
  /// oldest first; each turn a little higher than the one before.
  static func placeJournal(
    _ days: [Int], of graph: GraphSnapshot, ring: Float, into positions: inout [SIMD3<Float>]
  ) {
    let sorted = days.sorted {
      (graph.nodes[$0].journalDay ?? "") < (graph.nodes[$1].journalDay ?? "")
    }
    guard let first = sorted.first.map({ graph.nodes[$0].createdAt }) else { return }
    let perTurn: Float = 30
    for index in sorted {
      let n = Float((graph.nodes[index].createdAt.timeIntervalSince(first) / 86_400).rounded())
      let angle = n / perTurn * 2 * .pi
      let radius = ring * 0.75 + 1
      positions[index] = SIMD3(
        cos(angle) * radius, ring * 0.9 + 1.5 + n / perTurn * 0.8, sin(angle) * radius)
    }
  }

  /// `count` rounded up to the next step of a √2 ladder (1, 2, 3, 4, 6, 8,
  /// 12, 16, …), so sizes derived from it change only now and then.
  static func sizeStep(_ count: Int) -> Int {
    guard count > 1 else { return 1 }
    let steps = (2 * log2(Double(count))).rounded(.up)
    return Int(pow(2, steps / 2).rounded(.up))
  }

  /// A point spread evenly through the unit ball, keeping out of the very
  /// middle where the hub sits. Same generator, same point.
  static func pointInBall(_ rng: inout SeededRandom) -> SIMD3<Float> {
    for _ in 0..<64 {
      let point = SIMD3<Float>(rng.next(), rng.next(), rng.next())
      let length = simd_length_squared(point)
      if length <= 1, length >= 0.15 * 0.15 { return point }
    }
    return [0.5, 0, 0]
  }

  /// Point `i` of `count` spread evenly on the unit sphere.
  static func fibonacciSphere(_ i: Int, count: Int) -> SIMD3<Float> {
    guard count > 1 else { return SIMD3(0, 0, 0) }
    let golden = Float.pi * (3 - Float(5).squareRoot())
    let y = 1 - 2 * (Float(i) + 0.5) / Float(count)
    let r = (1 - y * y).squareRoot()
    let theta = golden * Float(i)
    return SIMD3(cos(theta) * r, y, sin(theta) * r)
  }
}

/// A tiny deterministic generator seeded from a string (FNV-1a + xorshift).
struct SeededRandom {
  private var state: UInt64

  init(_ seed: String) {
    let hash = Self.hash(seed)
    state = hash == 0 ? 0x9e37_79b9_7f4a_7c15 : hash
  }

  /// FNV-1a plus a splitmix64 finish: stable across launches (unlike
  /// Swift's `hashValue`), and ids that differ only in the last character
  /// ("e12", "e13") still land far apart.
  static func hash(_ text: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in text.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x100_0000_01b3
    }
    hash = (hash ^ (hash >> 30)) &* 0xbf58_476d_1ce4_e5b9
    hash = (hash ^ (hash >> 27)) &* 0x94d0_49bb_1331_11eb
    return hash ^ (hash >> 31)
  }

  /// A value in -1...1.
  mutating func next() -> Float {
    state ^= state << 13
    state ^= state >> 7
    state ^= state << 17
    return Float(state % 2_000_001) / 1_000_000 - 1
  }
}
