import MetalKit
import SwiftUI

struct MetalView: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        do {
            let metalContext = try MetalContext()
            let view = configuredView(device: metalContext.device)
            let renderer = try MetalRenderer(
                context: metalContext,
                colorPixelFormat: view.colorPixelFormat
            )
            context.coordinator.renderer = renderer
            model.renderer = renderer
            model.rendererError = nil
            view.delegate = renderer
            return view
        } catch let error as RendererError {
            model.rendererError = error
            return configuredView(device: nil)
        } catch {
            model.rendererError = .shaderCompilation(error.localizedDescription)
            return configuredView(device: nil)
        }
    }

    func updateNSView(_ view: MTKView, context: Context) {}

    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        view.delegate = nil
        coordinator.renderer = nil
    }

    private func configuredView(device: MTLDevice?) -> MTKView {
        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.clearColor = MTLClearColor(red: 0.01, green: 0.005, blue: 0.04, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        return view
    }

    final class Coordinator {
        var renderer: MetalRenderer?
    }
}
