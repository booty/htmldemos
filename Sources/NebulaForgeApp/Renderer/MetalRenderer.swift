import MetalKit
import NebulaForgeCore

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let context: MetalContext
    private let diagnosticPipeline: MTLRenderPipelineState
    private let fluidSolver: FluidSolver
    private let timeStepper = TimeStepper()
    private var parameters = SimulationParameters.default
    private var lastFrameTime: TimeInterval?
    private var elapsedTime: Float = 0
    private var frameIndex: UInt32 = 0

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
        fluidSolver = try FluidSolver(context: context, gridAxis: parameters.fluidGridAxis)
        super.init()
    }

    func draw(in view: MTKView) {
        guard
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = context.queue.makeCommandBuffer()
        else {
            return
        }

        commandBuffer.label = "Diagnostic Frame"
        let now = ProcessInfo.processInfo.systemUptime
        let wallDelta = lastFrameTime.map { now - $0 } ?? 1.0 / 60.0
        lastFrameTime = now
        let schedule = timeStepper.schedule(
            wallDelta: wallDelta,
            speed: parameters.simulationSpeed
        )
        for _ in 0..<schedule.stepCount {
            let uniforms = GPUUniforms(
                parameters: parameters,
                schedule: schedule,
                elapsedTime: elapsedTime,
                frameIndex: frameIndex,
                particleCapacity: 2_000_000
            )
            fluidSolver.encodeStep(
                commandBuffer: commandBuffer,
                uniforms: uniforms,
                force: .inactive
            )
            elapsedTime += schedule.stepDelta
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        encoder.label = "Diagnostic Gradient"
        encoder.setRenderPipelineState(diagnosticPipeline)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        frameIndex &+= 1
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
