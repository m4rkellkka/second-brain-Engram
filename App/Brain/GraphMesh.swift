import AppKit
import RealityKit
import simd

/// Builds one mesh for many spheres or many lines, so the whole graph is a
/// handful of entities instead of thousands: RealityKit draws each entity
/// separately, and merged meshes keep 2,000 nodes smooth.
enum GraphMesh {
  /// Unit icosahedron: 12 vertices, 20 faces. Plenty for small unlit dots.
  static let icosahedron: (vertices: [SIMD3<Float>], triangles: [UInt32]) = {
    let t: Float = (1 + Float(5).squareRoot()) / 2
    let raw: [SIMD3<Float>] = [
      [-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0],
      [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
      [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1],
    ]
    let faces: [UInt32] = [
      0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
      1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
      3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
      4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
    ]
    return (raw.map { simd_normalize($0) }, faces)
  }()

  static func spheres(at centers: [SIMD3<Float>], radius: Float) throws -> MeshResource? {
    guard !centers.isEmpty else { return nil }
    let shape = icosahedron
    var positions: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    positions.reserveCapacity(centers.count * shape.vertices.count)
    indices.reserveCapacity(centers.count * shape.triangles.count)
    for center in centers {
      let base = UInt32(positions.count)
      positions += shape.vertices.map { center + $0 * radius }
      indices += shape.triangles.map { base + $0 }
    }
    return try mesh(positions, indices)
  }

  /// Thin triangular prisms, visible from every angle without per-frame work.
  static func lines(_ segments: [(SIMD3<Float>, SIMD3<Float>)], width: Float) throws
    -> MeshResource?
  {
    guard !segments.isEmpty else { return nil }
    var positions: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    positions.reserveCapacity(segments.count * 6)
    indices.reserveCapacity(segments.count * 18)
    for (a, b) in segments {
      let axis = b - a
      guard simd_length(axis) > 0.0001 else { continue }
      let direction = simd_normalize(axis)
      let helper: SIMD3<Float> = abs(direction.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
      let u = simd_normalize(simd_cross(direction, helper))
      let v = simd_cross(direction, u)
      let base = UInt32(positions.count)
      for k in 0..<3 {
        let angle = Float(k) * 2 * .pi / 3
        let offset = (u * cos(angle) + v * sin(angle)) * width
        positions.append(a + offset)
        positions.append(b + offset)
      }
      for k in 0..<3 {
        let a0 = base + UInt32(2 * k), b0 = a0 + 1
        let a1 = base + UInt32(2 * ((k + 1) % 3)), b1 = a1 + 1
        indices += [a0, b0, b1, a0, b1, a1]
      }
    }
    return try mesh(positions, indices)
  }

  private static func mesh(_ positions: [SIMD3<Float>], _ indices: [UInt32]) throws -> MeshResource?
  {
    guard !indices.isEmpty else { return nil }
    var descriptor = MeshDescriptor(name: "graph")
    descriptor.positions = MeshBuffers.Positions(positions)
    descriptor.primitives = .triangles(indices)
    return try MeshResource.generate(from: [descriptor])
  }

  static func material(_ color: NSColor, opacity: Float = 1) -> UnlitMaterial {
    var material = UnlitMaterial(color: color)
    if opacity < 1 { material.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
    material.faceCulling = .none
    return material
  }
}
