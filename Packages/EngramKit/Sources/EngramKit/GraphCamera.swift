import simd

/// An orbit camera for the Brain graph: it circles `target` at `distance`.
/// The renderer and the hover/click picking use the same matrices, so a
/// click always lands on the dot that was drawn there.
public struct GraphCamera: Sendable, Equatable {
  public var target: SIMD3<Float> = .zero
  public var distance: Float = 30
  public var yaw: Float = 0
  public var pitch: Float = 0.3
  public var fieldOfView: Float = 50 * .pi / 180

  public init() {}

  public var eye: SIMD3<Float> {
    let offset = SIMD3<Float>(
      sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
    return target + offset * distance
  }

  public func view() -> simd_float4x4 {
    let f = simd_normalize(target - eye)
    let s = simd_normalize(simd_cross(f, [0, 1, 0]))
    let u = simd_cross(s, f)
    let e = eye
    return simd_float4x4(
      columns: (
        [s.x, u.x, -f.x, 0],
        [s.y, u.y, -f.y, 0],
        [s.z, u.z, -f.z, 0],
        [-simd_dot(s, e), -simd_dot(u, e), simd_dot(f, e), 1]
      ))
  }

  /// Right-handed perspective with Metal's 0…1 depth range.
  public func projection(aspect: Float) -> simd_float4x4 {
    let near: Float = 0.05
    let far: Float = 4_000
    let y = 1 / tan(fieldOfView / 2)
    let x = y / max(aspect, 0.01)
    let z = far / (near - far)
    return simd_float4x4(
      columns: (
        [x, 0, 0, 0],
        [0, y, 0, 0],
        [0, 0, z, -1],
        [0, 0, z * near, 0]
      ))
  }

  public func viewProjection(aspect: Float) -> simd_float4x4 {
    projection(aspect: aspect) * view()
  }

  /// Where a world point lands in a view of `size` points (origin top left),
  /// and its distance from the camera; nil when it is behind the camera.
  public func project(_ point: SIMD3<Float>, size: SIMD2<Float>) -> (SIMD2<Float>, Float)? {
    guard size.x > 0, size.y > 0 else { return nil }
    let clip = viewProjection(aspect: size.x / size.y) * SIMD4(point, 1)
    guard clip.w > 0.05 else { return nil }
    let ndc = SIMD2(clip.x, clip.y) / clip.w
    return (SIMD2((ndc.x + 1) / 2 * size.x, (1 - ndc.y) / 2 * size.y), clip.w)
  }

  /// How many points tall a sphere of `radius` looks at `depth` from the
  /// camera, in a view `height` points tall (its radius, not its diameter).
  public func screenRadius(of radius: Float, atDepth depth: Float, height: Float) -> Float {
    radius / tan(fieldOfView / 2) / max(depth, 0.001) * height / 2
  }

  /// The index of the point nearest to `location` within `radius` points,
  /// preferring points closer to the camera when several overlap.
  public func nearest(
    to location: SIMD2<Float>, among points: [SIMD3<Float>], size: SIMD2<Float>,
    radius: Float = 10
  ) -> Int? {
    var best: (index: Int, score: Float)?
    for (i, point) in points.enumerated() {
      guard let (screen, depth) = project(point, size: size) else { continue }
      let gap = simd_distance(screen, location)
      guard gap < radius else { continue }
      let score = gap + depth * 0.02
      if let current = best, current.score <= score { continue }
      best = (i, score)
    }
    return best?.index
  }
}
