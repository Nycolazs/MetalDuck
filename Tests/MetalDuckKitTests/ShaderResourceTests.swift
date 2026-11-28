import Metal
import Testing
@testable import MetalDuckKit

@Suite struct ShaderResourceTests {
    /// The shader ships as source and is compiled at launch. This fails if the resource
    /// stops being bundled, or if the source no longer compiles.
    @Test func presentShaderIsBundledAndCompiles() throws {
        let source = try RendererCoordinator.loadPresentShaderSource()
        for name in ["fragmentPresent", "flowInterpolate", "splatFlow", "blockSearchCoarse"] {
            #expect(source.contains(name), "Present.metal is missing \(name)")
        }
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let library = try device.makeLibrary(source: source, options: nil)
        #expect(library.makeFunction(name: "flowInterpolate") != nil)
    }
}
