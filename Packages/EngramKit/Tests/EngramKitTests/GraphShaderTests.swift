import Metal
import Testing
import simd

@testable import EngramKit

@Suite struct GraphShaderTests {
  /// The shaders compile at launch, so a typo would only show as an empty
  /// graph. Compile them here instead (skipped on machines without Metal).
  @Test func shadersCompile() throws {
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    let library = try device.makeLibrary(source: GraphShaders.source, options: nil)
    for name in ["spriteVertex", "spriteFragment", "lineVertex", "lineFragment"] {
      #expect(library.makeFunction(name: name) != nil, "missing \(name)")
    }
  }

  @Test func shapesTravelInTheStyle() {
    let star = GraphShaders.Sprite(position: .zero, color: .zero, shape: .star)
    #expect(star.style.y == 2)
    #expect(GraphShaders.Sprite(position: .zero, color: .zero).style.y == 0)
  }

  /// The Swift structs are copied byte for byte into Metal buffers, so
  /// their size must match the shader's (three float4 each).
  @Test func instanceLayoutsMatchTheShader() {
    #expect(MemoryLayout<GraphShaders.Sprite>.stride == 48)
    #expect(MemoryLayout<GraphShaders.Line>.stride == 48)
  }

  /// Dots used to take their size from the view-projection matrix, whose
  /// terms change as the camera turns, so seen from the side every dot
  /// collapsed into a dim vertical sliver. Draw one dot head-on and from
  /// the side and compare how many pixels it covers.
  @Test func dotsKeepTheirSizeAsTheCameraTurns() throws {
    guard let device = MTLCreateSystemDefaultDevice(), device.hasUnifiedMemory,
      let queue = device.makeCommandQueue()
    else { return }
    let library = try device.makeLibrary(source: GraphShaders.source, options: nil)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "spriteVertex")
    descriptor.fragmentFunction = library.makeFunction(name: "spriteFragment")
    descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
    let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

    struct Uniforms {
      var viewProjection: simd_float4x4
      var viewport: SIMD4<Float>
      var fog: SIMD4<Float>
    }

    func litPixels(yaw: Float) throws -> Int {
      let side = 128
      let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: side, height: side, mipmapped: false)
      textureDescriptor.usage = .renderTarget
      textureDescriptor.storageMode = .shared
      let texture = try #require(device.makeTexture(descriptor: textureDescriptor))
      let pass = MTLRenderPassDescriptor()
      pass.colorAttachments[0].texture = texture
      pass.colorAttachments[0].loadAction = .clear
      pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
      pass.colorAttachments[0].storeAction = .store

      var camera = GraphCamera()
      camera.yaw = yaw
      camera.pitch = 0.3
      camera.distance = 10
      var uniforms = Uniforms(
        viewProjection: camera.viewProjection(aspect: 1),
        viewport: [Float(side), Float(side), 0, 1_000],
        fog: [0.1, 1_000, 1, 1 / tan(camera.fieldOfView / 2)])
      var sprite = GraphShaders.Sprite(
        position: SIMD4(camera.target, 1), color: [1, 1, 1, 1], maxPixels: 1_000)

      let commands = try #require(queue.makeCommandBuffer())
      let encoder = try #require(commands.makeRenderCommandEncoder(descriptor: pass))
      encoder.setRenderPipelineState(pipeline)
      encoder.setVertexBytes(&sprite, length: MemoryLayout<GraphShaders.Sprite>.stride, index: 0)
      encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
      encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
      encoder.endEncoding()
      commands.commit()
      commands.waitUntilCompleted()

      var pixels = [UInt8](repeating: 0, count: side * side * 4)
      texture.getBytes(
        &pixels, bytesPerRow: side * 4, from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)
      return stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 128 }.count
    }

    let front = try litPixels(yaw: 0)
    let fromTheSide = try litPixels(yaw: .pi / 2)
    #expect(front > 50)
    #expect(abs(front - fromTheSide) <= front / 10)
  }
}
