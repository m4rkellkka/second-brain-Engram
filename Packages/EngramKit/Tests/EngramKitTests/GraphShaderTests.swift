import Metal
import Testing

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
}
