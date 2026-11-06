import Testing
import simd

@testable import EngramKit

@Suite struct GraphCameraTests {
  let size = SIMD2<Float>(800, 600)

  @Test func targetLandsInTheMiddle() throws {
    var camera = GraphCamera()
    camera.target = [3, -2, 5]
    camera.yaw = 1.1
    camera.pitch = -0.4
    let (point, depth) = try #require(camera.project(camera.target, size: size))
    #expect(abs(point.x - 400) < 0.01)
    #expect(abs(point.y - 300) < 0.01)
    #expect(abs(depth - camera.distance) < 0.01)
  }

  @Test func axesPointTheRightWay() throws {
    let camera = GraphCamera()  // looking from +z (tilted up a bit) toward the origin
    let (right, _) = try #require(camera.project([2, 0, 0], size: size))
    let (up, _) = try #require(camera.project([0, 2, 0], size: size))
    #expect(right.x > 400)
    #expect(up.y < 300)
  }

  @Test func pointsBehindTheCameraAreNotProjected() {
    var camera = GraphCamera()
    camera.pitch = 0
    #expect(camera.project([0, 0, 100], size: size) == nil)
  }

  @Test func nearestPrefersTheCloserOverlappingPoint() {
    var camera = GraphCamera()
    camera.pitch = 0
    // Both on the line of sight through the middle; the first is closer.
    let points: [SIMD3<Float>] = [[0, 0, 10], [0, 0, -10], [8, 0, 0]]
    #expect(camera.nearest(to: [400, 300], among: points, size: size) == 0)
    #expect(camera.nearest(to: [10, 10], among: points, size: size) == nil)
    // Hidden points (filtered out) can't be picked; the farther one wins.
    #expect(
      camera.nearest(to: [400, 300], among: points, size: size, isIncluded: { $0 != 0 }) == 1)
  }

  @Test func screenRadiusMatchesProjection() throws {
    let camera = GraphCamera()
    // A point one unit "up" from the target, seen from the camera.
    let (centre, depth) = try #require(camera.project(camera.target, size: size))
    let up = simd_normalize(
      simd_cross(simd_cross(camera.target - camera.eye, [0, 1, 0]), camera.target - camera.eye))
    let (edge, _) = try #require(camera.project(camera.target + up, size: size))
    let expected = simd_distance(centre, edge)
    #expect(abs(camera.screenRadius(of: 1, atDepth: depth, height: size.y) - expected) < 0.5)
  }
}
