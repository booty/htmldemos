import MetalKit

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let context: MetalContext
    private let diagnosticPipeline: MTLRenderPipelineState

    init(context: MetalContext, colorPixelFormat: MTLPixelFormat) throws {
        self.context = context

        guard let vertexFunction = context.library.makeFunction(name: "fullscreenVertex") else {
            throw RendererError.pipeline("diagnostic vertex function")
        }
        guard let fragmentFunction = context.library.makeFunction(name: "diagnosticFragment") else {
            throw RendererError.pipeline("diagnostic fragment function")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Diagnostic Gradient"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat

        do {
            diagnosticPipeline = try context.device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw RendererError.pipeline("diagnostic render pipeline: \(error.localizedDescription)")
        }
        super.init()
    }

    func draw(in view: MTKView) {
        guard
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = context.queue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            return
        }

        commandBuffer.label = "Diagnostic Frame"
        encoder.label = "Diagnostic Gradient"
        encoder.setRenderPipelineState(diagnosticPipeline)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
