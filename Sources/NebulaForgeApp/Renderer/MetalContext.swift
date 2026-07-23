import Foundation
import Metal

enum RendererError: LocalizedError, Equatable {
    case noMetalDevice
    case missingShaderResource(String)
    case shaderCompilation(String)
    case pipeline(String)

    var errorDescription: String? {
        switch self {
        case .noMetalDevice:
            "This Mac does not expose a Metal device."
        case .missingShaderResource(let name):
            "Missing Metal shader resource: \(name).metal"
        case .shaderCompilation(let message):
            "Metal shader compilation failed: \(message)"
        case .pipeline(let stage):
            "Metal pipeline creation failed for \(stage)."
        }
    }
}

final class MetalContext {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary

    init(bundle: Bundle = .module) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.noMetalDevice
        }
        guard let queue = device.makeCommandQueue() else {
            throw RendererError.pipeline("Metal command queue")
        }

        let shaderNames = ["Shared", "Fluid", "Particles", "PostProcess"]
        let sources = try shaderNames.compactMap { name -> String? in
            guard let url = bundle.url(
                forResource: name,
                withExtension: "metal",
                subdirectory: "Shaders"
            ) else {
                if name == "Shared" {
                    throw RendererError.missingShaderResource(name)
                }
                return nil
            }
            return try String(contentsOf: url, encoding: .utf8)
        }

        do {
            library = try device.makeLibrary(
                source: sources.joined(separator: "\n"),
                options: nil
            )
        } catch {
            throw RendererError.shaderCompilation(error.localizedDescription)
        }
        self.device = device
        self.queue = queue
    }
}
