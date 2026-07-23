import MetalKit
import NebulaForgeCore

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let context: MetalContext
    private let fluidSolver: FluidSolver
    private let particleSystem: ParticleSystem
    private let particleRenderer: ParticleRenderer
    private let postProcessor: PostProcessor
    private let timeStepper = TimeStepper()
    private var parameters = SimulationParameters.default
    private var lastFrameTime: TimeInterval?
    private var elapsedTime: Float = 0
    private var frameIndex: UInt32 = 0
    private var lastRenderScale: Float?
    private let interactionLock = NSLock()
    private var camera = Camera.default
    private var interactionForce = InteractionForce.inactive
    private(set) var lastEncodingError: RendererError?

    init(context: MetalContext, colorPixelFormat: MTLPixelFormat) throws {
        self.context = context
        fluidSolver = try FluidSolver(context: context, gridAxis: parameters.fluidGridAxis)
        particleSystem = try ParticleSystem(context: context)
        particleRenderer = try ParticleRenderer(
            context: context,
            particleBuffer: particleSystem.currentBuffer,
            destinationPixelFormat: colorPixelFormat
        )
        postProcessor = try PostProcessor(context: context)
        super.init()
    }

    func draw(in view: MTKView) {
        guard view.currentRenderPassDescriptor != nil, let drawable = view.currentDrawable else {
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

        guard let renderCommandBuffer = context.queue.makeCommandBuffer() else {
            return
        }
        renderCommandBuffer.label = "HDR Particle Frame"
        let validatedParameters = parameters.validated()
        if let lastRenderScale, lastRenderScale != validatedParameters.renderScale {
            postProcessor.resetTemporalHistory()
        }
        lastRenderScale = validatedParameters.renderScale
        let drawableSize = view.drawableSize
        let aspect = drawableSize.height > 0
            ? Float(drawableSize.width / drawableSize.height)
            : 1
        particleRenderer.frameState = ParticleRenderFrameState(
            viewProjection: cameraViewProjection(aspect: aspect),
            activeParticleCount: validatedParameters.activeParticles,
            particleSize: validatedParameters.particleSize,
            paletteIndex: validatedParameters.palette.rawValue,
            velocityColorMix: validatedParameters.velocityColorMix
        )
        do {
            try particleRenderer.encode(
                commandBuffer: renderCommandBuffer,
                drawableSize: drawableSize,
                renderScale: validatedParameters.renderScale
            )
            guard
                let hdrTexture = particleRenderer.hdrTexture,
                let depthTexture = particleRenderer.depthTexture
            else {
                throw RendererError.commandEncoding("particle post-process inputs")
            }
            try postProcessor.encode(
                commandBuffer: renderCommandBuffer,
                source: hdrTexture,
                depth: depthTexture,
                destination: drawable.texture,
                parameters: validatedParameters
            )
        } catch let error as RendererError {
            lastEncodingError = error
            return
        } catch {
            lastEncodingError = .commandEncoding(error.localizedDescription)
            return
        }
        lastEncodingError = nil
        renderCommandBuffer.present(drawable)
        renderCommandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        postProcessor.resetTemporalHistory()
    }

    func resetTemporalHistory() {
        postProcessor.resetTemporalHistory()
    }

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
