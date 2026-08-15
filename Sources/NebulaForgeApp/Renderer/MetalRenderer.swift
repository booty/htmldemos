import MetalKit
import NebulaForgeCore

struct RendererControlUpdate: Equatable, Sendable {
    let parameters: SimulationParameters
    let isPaused: Bool
    let singleStepCount: Int
    let resetsSimulation: Bool
    let resetsTemporalHistory: Bool
    fileprivate let simulationResetGeneration: UInt64
    fileprivate let temporalResetGeneration: UInt64

    let singleStepDelta: Float = 1.0 / 60.0
}

struct RendererCommandState {
    private(set) var parameters: SimulationParameters
    private(set) var isPaused = false
    private var singleStepCount = 0
    private var resetsSimulation = false
    private var resetsTemporalHistory = false
    private var simulationResetGeneration: UInt64 = 0
    private var temporalResetGeneration: UInt64 = 0

    init(parameters: SimulationParameters) {
        self.parameters = parameters.validated()
    }

    mutating func apply(_ command: RendererCommand) {
        switch command {
        case .apply(let candidate):
            let candidate = candidate.validated()
            if candidate.fluidGridAxis != parameters.fluidGridAxis {
                requestSimulationReset()
            } else if candidate.renderScale != parameters.renderScale {
                requestTemporalReset()
            }
            parameters = candidate
        case .reset(let candidate):
            parameters = candidate.validated()
            requestSimulationReset()
        case .setPaused(let paused):
            isPaused = paused
            if !paused {
                singleStepCount = 0
            }
        case .singleStep:
            if isPaused {
                singleStepCount += 1
            }
        }
    }

    mutating func consume() -> RendererControlUpdate {
        let update = RendererControlUpdate(
            parameters: parameters,
            isPaused: isPaused,
            singleStepCount: singleStepCount,
            resetsSimulation: resetsSimulation,
            resetsTemporalHistory: resetsTemporalHistory,
            simulationResetGeneration: simulationResetGeneration,
            temporalResetGeneration: temporalResetGeneration
        )
        singleStepCount = 0
        return update
    }

    mutating func acknowledgeResets(from update: RendererControlUpdate) {
        if update.resetsSimulation,
           update.simulationResetGeneration == simulationResetGeneration
        {
            resetsSimulation = false
        }
        if update.resetsTemporalHistory,
           update.temporalResetGeneration == temporalResetGeneration
        {
            resetsTemporalHistory = false
        }
    }

    private mutating func requestSimulationReset() {
        singleStepCount = 0
        resetsSimulation = true
        resetsTemporalHistory = true
        simulationResetGeneration &+= 1
        temporalResetGeneration &+= 1
    }

    private mutating func requestTemporalReset() {
        resetsTemporalHistory = true
        temporalResetGeneration &+= 1
    }
}

final class MetalRenderer: NSObject, MTKViewDelegate, RendererCommandTarget {
    private let context: MetalContext
    private let fluidSolver: FluidSolver
    private let particleSystem: ParticleSystem
    private let particleRenderer: ParticleRenderer
    private let postProcessor: PostProcessor
    private let timeStepper = TimeStepper()
    private let commandLock = NSLock()
    private var commandState = RendererCommandState(parameters: .default)
    private var parameters = SimulationParameters.default
    private var lastFrameTime: TimeInterval?
    private var elapsedTime: Float = 0
    private var frameIndex: UInt32 = 0
    private var isPaused = false
    private var cinematicOrbitPhase: Float = 0
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
        let rawWallDelta = lastFrameTime.map { now - $0 } ?? 1.0 / 60.0
        lastFrameTime = now
        let controlUpdate = consumeControlUpdate()
        let wasPaused = isPaused
        isPaused = controlUpdate.isPaused
        parameters = controlUpdate.parameters
        if parameters.automaticCinematicCamera {
            cinematicOrbitPhase += Float(min(max(rawWallDelta, 0), 1.0 / 15.0))
                * parameters.cameraOrbitSpeed
            cinematicOrbitPhase.formTruncatingRemainder(dividingBy: 2 * .pi)
        } else {
            cinematicOrbitPhase = 0
        }

        if controlUpdate.resetsTemporalHistory {
            postProcessor.resetTemporalHistory()
        }
        if controlUpdate.resetsSimulation {
            do {
                try encodeSimulationReset(parameters: parameters)
            } catch let error as RendererError {
                lastEncodingError = error
                return
            } catch {
                lastEncodingError = .commandEncoding(error.localizedDescription)
                return
            }
        }
        if controlUpdate.resetsSimulation || controlUpdate.resetsTemporalHistory {
            acknowledgeResets(from: controlUpdate)
        }

        let schedules: [StepSchedule]
        if isPaused {
            schedules = Array(
                repeating: StepSchedule(
                    stepCount: 1,
                    stepDelta: controlUpdate.singleStepDelta
                ),
                count: controlUpdate.singleStepCount
            )
        } else {
            let wallDelta = wasPaused ? 1.0 / 60.0 : rawWallDelta
            schedules = [
                timeStepper.schedule(
                    wallDelta: wallDelta,
                    speed: parameters.simulationSpeed
                ),
            ]
        }
        let force = interactionForceSnapshot()
        for schedule in schedules {
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
                    particleCapacity: ParticleSystem.maximumCapacity
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
            viewProjection: cameraViewProjection(
                aspect: aspect,
                parameters: validatedParameters
            ),
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

    func apply(_ parameters: SimulationParameters) {
        submit(.apply(parameters))
    }

    func reset(_ parameters: SimulationParameters) {
        submit(.reset(parameters))
    }

    func setPaused(_ paused: Bool) {
        submit(.setPaused(paused))
    }

    func singleStep() {
        submit(.singleStep)
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
        cameraViewProjection(aspect: aspect, parameters: parameters)
    }

    func cameraViewProjection(
        aspect: Float,
        parameters: SimulationParameters
    ) -> simd_float4x4 {
        interactionLock.lock()
        var camera = camera
        interactionLock.unlock()
        camera.fieldOfView = parameters.fieldOfViewDegrees * .pi / 180
        if parameters.automaticCinematicCamera {
            camera.yaw += cinematicOrbitPhase
        }
        return camera.viewProjection(aspect: aspect)
    }

    private func interactionForceSnapshot() -> InteractionForce {
        interactionLock.lock()
        let force = interactionForce
        interactionLock.unlock()
        return force
    }

    private func submit(_ command: RendererCommand) {
        commandLock.lock()
        commandState.apply(command)
        commandLock.unlock()
    }

    private func consumeControlUpdate() -> RendererControlUpdate {
        commandLock.lock()
        let update = commandState.consume()
        commandLock.unlock()
        return update
    }

    private func acknowledgeResets(from update: RendererControlUpdate) {
        commandLock.lock()
        commandState.acknowledgeResets(from: update)
        commandLock.unlock()
    }

    private func encodeSimulationReset(parameters: SimulationParameters) throws {
        try fluidSolver.resizeIfNeeded(gridAxis: parameters.fluidGridAxis)
        guard let commandBuffer = context.queue.makeCommandBuffer() else {
            throw RendererError.commandEncoding("simulation reset command buffer")
        }
        commandBuffer.label = "Reset Simulation State"
        let schedule = StepSchedule(stepCount: 1, stepDelta: 1.0 / 60.0)
        let uniforms = GPUUniforms(
            parameters: parameters,
            schedule: schedule,
            elapsedTime: 0,
            frameIndex: 0,
            particleCapacity: ParticleSystem.maximumCapacity
        )
        let pendingFluidState = try fluidSolver.encodeReset(
            commandBuffer: commandBuffer,
            uniforms: uniforms
        )
        try particleSystem.encodeReset(
            commandBuffer: commandBuffer,
            parameters: parameters
        )
        commandBuffer.commit()
        fluidSolver.publishStep(pendingFluidState)
        elapsedTime = 0
        frameIndex = 0
    }
}
