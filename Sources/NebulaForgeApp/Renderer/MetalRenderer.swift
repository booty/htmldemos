import MetalKit
import NebulaForgeCore

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let context: MetalContext
    private let diagnosticPipeline: MTLRenderPipelineState
    private let fluidSolver: FluidSolver
    private let particleSystem: ParticleSystem
    private let timeStepper = TimeStepper()
    private var parameters = SimulationParameters.default
    private var lastFrameTime: TimeInterval?
    private var elapsedTime: Float = 0
    private var frameIndex: UInt32 = 0
    private let interactionLock = NSLock()
    private var camera = Camera.default
    private var interactionForce = InteractionForce.inactive
    private(set) var lastEncodingError: RendererError?

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
        particleSystem = try ParticleSystem(context: context)
        super.init()
    }

    func draw(in view: MTKView) {
        guard
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable
        else {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let wallDelta = lastFrameTime.map { now - $0 } ?? 1.0 / 60.0
        lastFrameTime = now
        let schedule = timeStepper.schedule(
            wallDelta: wallDelta,
            speed: parameters.simulationSpeed
        )
        let force = interactionForceSnapshot()
        for step in 0..<schedule.stepCount {
            guard let simulationCommandBuffer = context.queue.makeCommandBuffer() else {
                lastEncodingError = .commandEncoding("simulation command buffer")
                return
            }
            simulationCommandBuffer.label = "Fluid Step \(step + 1)"
            let uniforms = GPUUniforms(
                parameters: parameters,
                schedule: schedule,
                elapsedTime: elapsedTime,
                frameIndex: frameIndex,
                particleCapacity: 2_000_000
            )
            var particleUniforms = uniforms
            particleUniforms.deltaAndTime.y += schedule.stepDelta
            do {
                let pendingFluidState = try fluidSolver.encodeStep(
                    commandBuffer: simulationCommandBuffer,
                    uniforms: uniforms,
                    force: force
                )
                try particleSystem.encodeUpdate(
                    commandBuffer: simulationCommandBuffer,
                    velocityTexture: fluidSolver.velocityTexture(for: pendingFluidState),
                    uniforms: particleUniforms
                )
                fluidSolver.publishStep(pendingFluidState)
            } catch let error as RendererError {
                lastEncodingError = error
                return
            } catch {
                lastEncodingError = .commandEncoding(error.localizedDescription)
                return
            }
            simulationCommandBuffer.commit()
            elapsedTime += schedule.stepDelta
            frameIndex &+= 1
        }
        lastEncodingError = nil

        guard
            let renderCommandBuffer = context.queue.makeCommandBuffer(),
            let encoder = renderCommandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
            )
        else {
            return
        }
        renderCommandBuffer.label = "Diagnostic Frame"
        encoder.label = "Diagnostic Gradient"
        encoder.setRenderPipelineState(diagnosticPipeline)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        renderCommandBuffer.present(drawable)
        renderCommandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func updateCamera(_ camera: Camera) {
        interactionLock.lock()
        self.camera = camera
        interactionLock.unlock()
    }

    func updateInteractionForce(_ force: InteractionForce?) {
        interactionLock.lock()
        interactionForce = force ?? .inactive
        interactionLock.unlock()
    }

    func cameraViewProjection(aspect: Float) -> simd_float4x4 {
        interactionLock.lock()
        let camera = camera
        interactionLock.unlock()
        return camera.viewProjection(aspect: aspect)
    }

    private func interactionForceSnapshot() -> InteractionForce {
        interactionLock.lock()
        let force = interactionForce
        interactionLock.unlock()
        return force
    }
}
