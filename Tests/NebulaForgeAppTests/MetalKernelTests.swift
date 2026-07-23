import XCTest
import Metal
import NebulaForgeCore
import simd
@testable import NebulaForgeApp

final class MetalKernelTests: XCTestCase {
    func testParticleLifetimeUsesValidatedMinimumDefaultAndMaximum() throws {
        let harness = try MetalTestHarness(gridAxis: 8, particleCount: 64)

        for lifetime: Float in [0.5, 7, 20] {
            var parameters = SimulationParameters.default
            parameters.particleLifetime = lifetime
            try harness.initializeParticles(parameters: parameters)

            for particle in try harness.readParticles() {
                XCTAssertEqual(particle.lifetime, lifetime)
            }
        }
    }

    func testRespawnUsesValidatedMinimumDefaultAndMaximumLifetime() throws {
        let harness = try MetalTestHarness(gridAxis: 8, particleCount: 64)

        for lifetime: Float in [0.5, 7, 20] {
            var parameters = SimulationParameters.default
            parameters.particleLifetime = lifetime
            parameters.emissionRate = 500_000
            harness.setParticleParameters(parameters)
            try harness.seedExpiredParticles()
            try harness.updateParticles(delta: 1.0 / 60.0)
            try harness.updateParticles(delta: 1.0 / 60.0)

            for particle in try harness.readParticles() {
                XCTAssertEqual(particle.lifetime, lifetime)
            }
        }
    }

    func testZeroEmitterSpreadPreservesNormalizedDirection() throws {
        let harness = try MetalTestHarness(gridAxis: 8, particleCount: 64)
        var parameters = SimulationParameters.default
        parameters.emitterDirection = SIMD3(0, 1, 0)
        parameters.emitterSpread = 0
        parameters.emitterInitialVelocity = 2
        parameters.emissionRate = 500_000
        harness.setParticleParameters(parameters)
        try harness.seedExpiredParticles()
        try harness.updateParticles(delta: 1.0 / 60.0)
        try harness.updateParticles(delta: 1.0 / 60.0)

        for particle in try harness.readParticles() {
            XCTAssertEqual(particle.velocitySeed.x, 0)
            XCTAssertEqual(particle.velocitySeed.y, 2)
            XCTAssertEqual(particle.velocitySeed.z, 0)
        }
    }

    func testNonzeroEmitterSpreadVariesLaunchDirections() throws {
        let harness = try MetalTestHarness(gridAxis: 8, particleCount: 64)
        var parameters = SimulationParameters.default
        parameters.emitterDirection = SIMD3(0, 1, 0)
        parameters.emitterSpread = 0.5
        parameters.emitterInitialVelocity = 1
        parameters.emissionRate = 500_000
        harness.setParticleParameters(parameters)
        try harness.seedExpiredParticles()
        try harness.updateParticles(delta: 1.0 / 60.0)
        try harness.updateParticles(delta: 1.0 / 60.0)

        let directions = try harness.readParticles().map {
            SIMD3($0.velocitySeed.x, $0.velocitySeed.y, $0.velocitySeed.z)
        }
        XCTAssertTrue(directions.allSatisfy { direction in
            direction.x.isFinite
                && direction.y.isFinite
                && direction.z.isFinite
                && abs(simd_length(direction) - 1) < 0.000_01
        })
        let minimumConeDot = Float(cos(Double.pi / 4))
        XCTAssertTrue(directions.allSatisfy {
            simd_dot($0, SIMD3(0, 1, 0)) >= minimumConeDot - 0.000_01
        })
        XCTAssertTrue(directions.contains { simd_dot($0, SIMD3(0, 1, 0)) < 0.999 })
        XCTAssertTrue(directions.dropFirst().contains { simd_distance($0, directions[0]) > 0.001 })
    }

    func testEmissionRateControlsDormantActivationOverFixedInterval() throws {
        let lowRateHarness = try MetalTestHarness(gridAxis: 8, particleCount: 64)
        var lowRate = SimulationParameters.default
        lowRate.emissionRate = 1_000
        try lowRateHarness.initializeParticles(parameters: lowRate)
        try lowRateHarness.updateParticles(delta: 0.004)

        let highRateHarness = try MetalTestHarness(gridAxis: 8, particleCount: 64)
        var highRate = SimulationParameters.default
        highRate.emissionRate = 500_000
        try highRateHarness.initializeParticles(parameters: highRate)
        try highRateHarness.updateParticles(delta: 0.004)

        let lowRateParticles = try lowRateHarness.readParticles()
        let highRateParticles = try highRateHarness.readParticles()
        let lowRateAlive = lowRateParticles.filter { $0.age >= 0 }.count
        let highRateAlive = highRateParticles.filter { $0.age >= 0 }.count
        XCTAssertLessThan(lowRateAlive, highRateAlive)
        XCTAssertTrue(lowRateParticles.contains { $0.isDormant })
        XCTAssertEqual(highRateAlive, 64)
    }

    func testEmissionRateControlsExpiredParticleRecycling() throws {
        let lowRateHarness = try MetalTestHarness(gridAxis: 8, particleCount: 64)
        var lowRate = SimulationParameters.default
        lowRate.emissionRate = 1_000
        lowRateHarness.setParticleParameters(lowRate)
        try lowRateHarness.seedExpiredParticles()
        try lowRateHarness.updateParticles(delta: 1.0 / 60.0)
        try lowRateHarness.updateParticles(delta: 1.0 / 60.0)

        let highRateHarness = try MetalTestHarness(gridAxis: 8, particleCount: 64)
        var highRate = SimulationParameters.default
        highRate.emissionRate = 500_000
        highRateHarness.setParticleParameters(highRate)
        try highRateHarness.seedExpiredParticles()
        try highRateHarness.updateParticles(delta: 1.0 / 60.0)
        try highRateHarness.updateParticles(delta: 1.0 / 60.0)

        let lowRateAlive = try lowRateHarness.readParticles().filter { $0.age >= 0 }.count
        let highRateAlive = try highRateHarness.readParticles().filter { $0.age >= 0 }.count
        XCTAssertLessThan(lowRateAlive, highRateAlive)
        XCTAssertGreaterThan(lowRateAlive, 0)
        XCTAssertEqual(highRateAlive, 64)
    }

    func testRepeatingEmissionPhasesTrackRateAcrossMultipleLifetimes() throws {
        let particleCount = 1_024
        let lifetime: Float = 0.5
        let duration: Float = 2.5
        let delta: Float = 0.002

        func observedTransitions(rate: Float) throws -> Int {
            let harness = try MetalTestHarness(gridAxis: 8, particleCount: particleCount)
            var parameters = SimulationParameters.default
            parameters.particleLifetime = lifetime
            parameters.emissionRate = rate
            parameters.emitterInitialVelocity = 0
            try harness.initializeParticles(parameters: parameters)
            return try harness.countDormantToActiveTransitions(duration: duration, delta: delta)
        }

        let lowRate: Float = 1_000
        let highRate: Float = 4_000
        let lowObserved = try observedTransitions(rate: lowRate)
        let highObserved = try observedTransitions(rate: highRate)
        let lifetimeCapacity = Float(particleCount) / lifetime
        let lowExpected = min(lowRate, lifetimeCapacity) * duration
        let highExpected = min(highRate, lifetimeCapacity) * duration
        let tolerance: Float = 0.15

        XCTAssertLessThan(lowObserved, highObserved)
        XCTAssertLessThanOrEqual(
            abs(Float(lowObserved) - lowExpected),
            lowExpected * tolerance
        )
        XCTAssertLessThanOrEqual(
            abs(Float(highObserved) - highExpected),
            highExpected * tolerance
        )
    }

    func testLiveLowToHighRateActivatesWithinNewCycle() throws {
        let harness = try MetalTestHarness(gridAxis: 8, particleCount: 1_024)
        var parameters = SimulationParameters.default
        parameters.particleLifetime = 20
        parameters.emissionRate = 1_000
        try harness.initializeParticles(parameters: parameters)
        try harness.updateParticles(delta: 0.02)
        let aliveBeforeChange = try harness.readParticles().filter { !$0.isDormant }.count

        parameters.emissionRate = 500_000
        harness.setParticleParameters(parameters)
        try harness.updateParticles(delta: 0.005)
        let aliveAfterChange = try harness.readParticles().filter { !$0.isDormant }.count

        XCTAssertLessThan(aliveBeforeChange, 50)
        XCTAssertEqual(aliveAfterChange, 1_024)
    }

    func testLiveHighToLowRateSlowsWithoutDelayedBatch() throws {
        let harness = try MetalTestHarness(gridAxis: 8, particleCount: 1_024)
        var parameters = SimulationParameters.default
        parameters.particleLifetime = 0.5
        parameters.emissionRate = 4_000
        harness.setParticleParameters(parameters)
        try harness.seedExpiredParticles()
        try harness.updateParticles(delta: 0.001)

        parameters.emissionRate = 1_000
        harness.setParticleParameters(parameters)
        let transitions = try harness.countDormantToActiveTransitions(
            duration: 0.1,
            delta: 0.01
        )

        XCTAssertGreaterThanOrEqual(transitions, 80)
        XCTAssertLessThanOrEqual(transitions, 120)
    }

    func testExpiredParticlesRespawnInsideEmitter() throws {
        let harness = try MetalTestHarness(gridAxis: 8, particleCount: 64)
        try harness.seedExpiredParticles()
        try harness.updateParticles(delta: 1.0 / 60.0)
        try harness.updateParticles(delta: 1.0 / 60.0)
        let firstRespawn = try harness.readParticles()

        try harness.seedExpiredParticles()
        try harness.updateParticles(delta: 1.0 / 60.0)
        try harness.updateParticles(delta: 1.0 / 60.0)
        let secondRespawn = try harness.readParticles()

        for (first, second) in zip(firstRespawn, secondRespawn) {
            XCTAssertEqual(first.positionAge, second.positionAge)
            XCTAssertEqual(first.previousPositionLifetime, second.previousPositionLifetime)
            XCTAssertEqual(first.velocitySeed, second.velocitySeed)
        }

        for particle in firstRespawn {
            XCTAssertTrue(particle.positionAge.x.isFinite)
            XCTAssertTrue(particle.positionAge.y.isFinite)
            XCTAssertTrue(particle.positionAge.z.isFinite)
            XCTAssertTrue(particle.age.isFinite)
            XCTAssertTrue(particle.lifetime.isFinite)
            XCTAssertTrue(particle.velocitySeed.x.isFinite)
            XCTAssertTrue(particle.velocitySeed.y.isFinite)
            XCTAssertTrue(particle.velocitySeed.z.isFinite)
            XCTAssertTrue(particle.velocitySeed.w.isFinite)
            XCTAssertGreaterThanOrEqual(particle.age, 0)
            XCTAssertLessThan(particle.age, particle.lifetime)
            XCTAssertLessThanOrEqual(simd_length(particle.position), 0.120_001)
            XCTAssertLessThanOrEqual(simd_length(particle.position), 1.0)
        }
    }

    func testProductionFluidResourcesStayPrivateAndResizeOnlyForAxisChanges() throws {
        let context = try MetalContext()
        let solver = try FluidSolver(context: context, gridAxis: .n48)
        let originalVelocity = solver.velocityTexture

        XCTAssertEqual(originalVelocity.storageMode, .private)
        try solver.resizeIfNeeded(gridAxis: .n48)
        XCTAssertTrue(originalVelocity === solver.velocityTexture)

        try solver.resizeIfNeeded(gridAxis: .n64)
        XCTAssertFalse(originalVelocity === solver.velocityTexture)
        XCTAssertEqual(solver.velocityTexture.width, 64)
        XCTAssertEqual(solver.velocityTexture.storageMode, .private)
    }

    func testProjectionReducesDivergence() throws {
        let harness = try MetalTestHarness(gridAxis: 8)
        try harness.seedRadialVelocity()
        let before = try harness.maximumAbsoluteDivergence()
        try harness.project(iterations: 40)
        let after = try harness.maximumAbsoluteDivergence()

        XCTAssertLessThan(after, before * 0.35)
        XCTAssertTrue(after.isFinite)
    }

    func testAllocationFailurePreservesCompleteExistingResourceSet() throws {
        let context = try MetalContext()
        let gate = TextureAllocationGate(device: context.device)
        let solver = try FluidSolver(
            context: context,
            gridAxis: 8,
            storageMode: .shared,
            textureFactory: gate.makeTexture
        )
        let originalVelocity = solver.velocityTexture
        let originalPressure = solver.pressureTexture
        let originalState = solver.stepState

        gate.successesBeforeFailure = 2

        XCTAssertThrowsError(try solver.resizeIfNeeded(gridAxis: 9))
        XCTAssertTrue(originalVelocity === solver.velocityTexture)
        XCTAssertTrue(originalPressure === solver.pressureTexture)
        XCTAssertEqual(solver.gridAxis, 8)
        XCTAssertEqual(solver.stepState, originalState)
    }

    func testEncoderFailureDoesNotPublishPendingPingPongState() throws {
        let context = try MetalContext()
        let gate = EncoderCreationGate(successesBeforeFailure: 5)
        let solver = try FluidSolver(
            context: context,
            gridAxis: 8,
            storageMode: .shared,
            encoderFactory: gate.makeEncoder
        )
        let initialState = solver.stepState
        let commandBuffer = try XCTUnwrap(context.queue.makeCommandBuffer())

        XCTAssertThrowsError(
            try solver.encodeStep(
                commandBuffer: commandBuffer,
                uniforms: quiescentUniforms(gridAxis: 8),
                force: .inactive
            )
        ) { error in
            guard case RendererError.commandEncoding = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(solver.stepState, initialState)
    }

    func testParticleEncoderFailureDoesNotPublishFluidStepState() throws {
        let context = try MetalContext()
        let solver = try FluidSolver(
            context: context,
            gridAxis: 8,
            storageMode: .shared
        )
        let gate = EncoderCreationGate(successesBeforeFailure: 0)
        let particleSystem = try ParticleSystem(
            context: context,
            updateEncoderFactory: gate.makeEncoder
        )
        let initialFluidState = solver.stepState
        let originalParticleBuffer = particleSystem.currentBuffer
        let commandBuffer = try XCTUnwrap(context.queue.makeCommandBuffer())
        let uniforms = quiescentUniforms(gridAxis: 8)

        let pendingFluidState = try solver.encodeStep(
            commandBuffer: commandBuffer,
            uniforms: uniforms,
            force: .inactive
        )
        XCTAssertNotEqual(pendingFluidState, initialFluidState)
        XCTAssertThrowsError(
            try particleSystem.encodeUpdate(
                commandBuffer: commandBuffer,
                velocityTexture: solver.velocityTexture(for: pendingFluidState),
                uniforms: uniforms
            )
        ) { error in
            guard case RendererError.commandEncoding("particle update") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(solver.stepState, initialFluidState)
        XCTAssertTrue(originalParticleBuffer === particleSystem.currentBuffer)
        XCTAssertEqual(commandBuffer.status, .notEnqueued)
    }

    func testRepeatedAsymmetricBoundaryStepsStayFiniteAndProjected() throws {
        let context = try MetalContext()
        let solver = try FluidSolver(
            context: context,
            gridAxis: 8,
            storageMode: .shared
        )
        let harness = try MetalTestHarness(context: context, gridAxis: 8)
        harness.seedAsymmetricBoundaryVelocity(texture: solver.velocityTexture)
        let before = try harness.maximumAbsoluteDivergence(texture: solver.velocityTexture)
        let uniforms = quiescentUniforms(gridAxis: 8)

        for _ in 0..<16 {
            let commandBuffer = try XCTUnwrap(context.queue.makeCommandBuffer())
            let pendingState = try solver.encodeStep(
                commandBuffer: commandBuffer,
                uniforms: uniforms,
                force: .inactive
            )
            solver.publishStep(pendingState)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            XCTAssertEqual(commandBuffer.status, .completed)
            XCTAssertTrue(harness.allValuesAreFinite(texture: solver.velocityTexture, components: 4))
            XCTAssertTrue(harness.allValuesAreFinite(texture: solver.pressureTexture, components: 1))
        }

        let after = try harness.maximumAbsoluteDivergence(texture: solver.velocityTexture)
        XCTAssertLessThan(after, before * 0.6)
        XCTAssertLessThan(harness.maximumAbsoluteValue(texture: solver.pressureTexture, components: 1), 64)
    }
}

private final class TextureAllocationGate {
    let device: MTLDevice
    var successesBeforeFailure: Int?

    init(device: MTLDevice) {
        self.device = device
    }

    func makeTexture(descriptor: MTLTextureDescriptor) -> MTLTexture? {
        if let remaining = successesBeforeFailure {
            guard remaining > 0 else { return nil }
            successesBeforeFailure = remaining - 1
        }
        return device.makeTexture(descriptor: descriptor)
    }
}

private final class EncoderCreationGate {
    var successesBeforeFailure: Int

    init(successesBeforeFailure: Int) {
        self.successesBeforeFailure = successesBeforeFailure
    }

    func makeEncoder(commandBuffer: MTLCommandBuffer) -> MTLComputeCommandEncoder? {
        guard successesBeforeFailure > 0 else { return nil }
        successesBeforeFailure -= 1
        return commandBuffer.makeComputeCommandEncoder()
    }
}

private func quiescentUniforms(gridAxis: Int) -> GPUUniforms {
    var parameters = SimulationParameters.default
    parameters.velocityDissipation = 0
    parameters.viscosity = 0
    parameters.gravityMagnitude = 0
    parameters.attractionMagnitude = 0
    parameters.orbitalForceMagnitude = 0
    parameters.vorticityStrength = 0
    parameters.turbulenceStrength = 0
    parameters.emitterInitialVelocity = 0
    var uniforms = GPUUniforms(
        parameters: parameters,
        schedule: StepSchedule(stepCount: 1, stepDelta: 1.0 / 60.0),
        elapsedTime: 0,
        frameIndex: 0,
        particleCapacity: 2_000_000
    )
    let axis = UInt32(gridAxis)
    uniforms.gridSize = SIMD4(axis, axis, axis, 0)
    return uniforms
}

private enum MetalHarnessError: Error {
    case missingPipeline(String)
    case resourceAllocation(String)
    case commandEncoding
    case commandFailure(Error?)
}

private final class MetalTestHarness {
    private let context: MetalContext
    private let gridAxis: Int
    private let computeDivergencePipeline: MTLComputePipelineState
    private let jacobiPressurePipeline: MTLComputePipelineState
    private let subtractPressureGradientPipeline: MTLComputePipelineState
    private var velocityTextures: [MTLTexture]
    private var pressureTextures: [MTLTexture]
    private let divergenceTexture: MTLTexture
    private let initializeParticlesPipeline: MTLComputePipelineState?
    private let updateParticlesPipeline: MTLComputePipelineState?
    private let particleBuffer: MTLBuffer?
    private let particleCount: Int
    private var velocityIndex = 0
    private var pressureIndex = 0
    private var uniforms: GPUUniforms
    private var particleElapsedTime: Float = 0

    init(context: MetalContext? = nil, gridAxis: Int, particleCount: Int = 0) throws {
        if let context {
            self.context = context
        } else {
            self.context = try MetalContext()
        }
        self.gridAxis = gridAxis
        self.particleCount = particleCount
        computeDivergencePipeline = try Self.pipeline(named: "computeDivergence", context: self.context)
        jacobiPressurePipeline = try Self.pipeline(named: "jacobiPressure", context: self.context)
        subtractPressureGradientPipeline = try Self.pipeline(
            named: "subtractPressureGradient",
            context: self.context
        )
        velocityTextures = try [
            Self.texture(context: self.context, format: .rgba16Float, axis: gridAxis),
            Self.texture(context: self.context, format: .rgba16Float, axis: gridAxis),
        ]
        pressureTextures = try [
            Self.texture(context: self.context, format: .r16Float, axis: gridAxis),
            Self.texture(context: self.context, format: .r16Float, axis: gridAxis),
        ]
        divergenceTexture = try Self.texture(
            context: self.context,
            format: .r16Float,
            axis: gridAxis
        )
        if particleCount > 0 {
            initializeParticlesPipeline = try Self.pipeline(
                named: "initializeParticles",
                context: self.context
            )
            updateParticlesPipeline = try Self.pipeline(named: "updateParticles", context: self.context)
            particleBuffer = self.context.device.makeBuffer(
                length: particleCount * MemoryLayout<GPUParticle>.stride,
                options: .storageModeShared
            )
        } else {
            initializeParticlesPipeline = nil
            updateParticlesPipeline = nil
            particleBuffer = nil
        }
        uniforms = GPUUniforms(
            parameters: .default,
            schedule: StepSchedule(stepCount: 1, stepDelta: 1.0 / 60.0),
            elapsedTime: 0,
            frameIndex: 0,
            particleCapacity: 2_000_000
        )
        let axis = UInt32(gridAxis)
        uniforms.gridSize = SIMD4(axis, axis, axis, 0)
    }

    func initializeParticles(parameters: SimulationParameters) throws {
        guard let initializeParticlesPipeline, let particleBuffer else {
            throw MetalHarnessError.resourceAllocation("particle resources")
        }
        particleElapsedTime = 0
        setParticleParameters(parameters)
        var initialization = SIMD4<UInt32>(0x4e_46_47_31, UInt32(particleCount), 0, 0)
        guard
            let initializationBuffer = context.device.makeBuffer(
                bytes: &initialization,
                length: MemoryLayout<SIMD4<UInt32>>.stride,
                options: .storageModeShared
            ),
            let commandBuffer = context.queue.makeCommandBuffer(),
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw MetalHarnessError.commandEncoding
        }
        encoder.setComputePipelineState(initializeParticlesPipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBuffer(initializationBuffer, offset: 0, index: 1)
        setUniforms(on: encoder, index: 2)
        dispatchParticles(encoder: encoder, pipeline: initializeParticlesPipeline)
        encoder.endEncoding()
        try commitAndWait(commandBuffer)
    }

    func setParticleParameters(_ parameters: SimulationParameters) {
        uniforms = GPUUniforms(
            parameters: parameters,
            schedule: StepSchedule(stepCount: 1, stepDelta: uniforms.deltaAndTime.x),
            elapsedTime: particleElapsedTime,
            frameIndex: uniforms.particleCounts.z,
            particleCapacity: particleCount
        )
        let axis = UInt32(gridAxis)
        uniforms.gridSize = SIMD4(axis, axis, axis, 0)
        uniforms.particleCounts.x = UInt32(particleCount)
        uniforms.particleCounts.y = UInt32(particleCount)
    }

    func seedExpiredParticles() throws {
        guard let particleBuffer else {
            throw MetalHarnessError.resourceAllocation("particle buffer")
        }
        let particles = particleBuffer.contents().bindMemory(
            to: GPUParticle.self,
            capacity: particleCount
        )
        for index in 0..<particleCount {
            particles[index] = GPUParticle(
                positionAge: SIMD4(0, 0, 0, 2),
                previousPositionLifetime: SIMD4(0, 0, 0, 1),
                velocitySeed: SIMD4(0, 0, 0, Float(index + 1))
            )
        }
    }

    func updateParticles(delta: Float) throws {
        guard let updateParticlesPipeline, let particleBuffer else {
            throw MetalHarnessError.resourceAllocation("particle resources")
        }
        uniforms.deltaAndTime.x = delta
        particleElapsedTime += delta
        uniforms.deltaAndTime.y = particleElapsedTime
        uniforms.particleCounts.x = UInt32(particleCount)
        uniforms.particleCounts.y = UInt32(particleCount)
        guard
            let commandBuffer = context.queue.makeCommandBuffer(),
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw MetalHarnessError.commandEncoding
        }
        encoder.setComputePipelineState(updateParticlesPipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setTexture(velocityTextures[velocityIndex], index: 0)
        setUniforms(on: encoder, index: 1)
        dispatchParticles(encoder: encoder, pipeline: updateParticlesPipeline)
        encoder.endEncoding()
        try commitAndWait(commandBuffer)
    }

    func countDormantToActiveTransitions(duration: Float, delta: Float) throws -> Int {
        var previousDormancy = try readParticles().map(\.isDormant)
        var transitions = 0
        let stepCount = Int((duration / delta).rounded())

        for _ in 0..<stepCount {
            try updateParticles(delta: delta)
            let currentDormancy = try readParticles().map(\.isDormant)
            transitions += zip(previousDormancy, currentDormancy).filter {
                $0.0 && !$0.1
            }.count
            previousDormancy = currentDormancy
        }
        return transitions
    }

    func readParticles() throws -> [GPUParticle] {
        guard let particleBuffer else {
            throw MetalHarnessError.resourceAllocation("particle buffer")
        }
        let particles = particleBuffer.contents().bindMemory(
            to: GPUParticle.self,
            capacity: particleCount
        )
        return Array(UnsafeBufferPointer(start: particles, count: particleCount))
    }

    func seedRadialVelocity() throws {
        var values = [Float16](repeating: 0, count: gridAxis * gridAxis * gridAxis * 4)
        let halfAxis = Float(gridAxis) * 0.5
        for z in 0..<gridAxis {
            for y in 0..<gridAxis {
                for x in 0..<gridAxis {
                    let position = SIMD3<Float>(
                        (Float(x) + 0.5 - halfAxis) / halfAxis,
                        (Float(y) + 0.5 - halfAxis) / halfAxis,
                        (Float(z) + 0.5 - halfAxis) / halfAxis
                    )
                    let falloff = exp(-3 * simd_dot(position, position))
                    let velocity = position * falloff * 4
                    let index = ((z * gridAxis + y) * gridAxis + x) * 4
                    values[index] = Float16(velocity.x)
                    values[index + 1] = Float16(velocity.y)
                    values[index + 2] = Float16(velocity.z)
                }
            }
        }
        write(values, to: velocityTextures[velocityIndex], components: 4)
    }

    func maximumAbsoluteDivergence() throws -> Float {
        try maximumAbsoluteDivergence(texture: velocityTextures[velocityIndex])
    }

    func maximumAbsoluteDivergence(texture: MTLTexture) throws -> Float {
        guard let commandBuffer = context.queue.makeCommandBuffer() else {
            throw MetalHarnessError.commandEncoding
        }
        try encodeDivergence(commandBuffer: commandBuffer, velocity: texture)
        try commitAndWait(commandBuffer)

        var values = [Float16](repeating: 0, count: gridAxis * gridAxis * gridAxis)
        read(texture: divergenceTexture, into: &values, components: 1)
        return values.lazy.map { abs(Float($0)) }.max() ?? 0
    }

    func seedAsymmetricBoundaryVelocity(texture: MTLTexture) {
        var values = [Float16](repeating: 0, count: gridAxis * gridAxis * gridAxis * 4)
        let halfAxis = Float(gridAxis) * 0.5
        for z in 0..<gridAxis {
            for y in 0..<gridAxis {
                for x in 0..<gridAxis {
                    let position = SIMD3<Float>(
                        (Float(x) + 0.5 - halfAxis) / halfAxis,
                        (Float(y) + 0.5 - halfAxis) / halfAxis,
                        (Float(z) + 0.5 - halfAxis) / halfAxis
                    )
                    let offset = position - SIMD3<Float>(0.25, -0.15, 0.1)
                    let falloff = exp(-2.5 * simd_dot(offset, offset))
                    var velocity = offset * falloff * 3
                    if x == 0 {
                        velocity.x -= 1.5 * (1 + 0.2 * position.y)
                    }
                    let index = ((z * gridAxis + y) * gridAxis + x) * 4
                    values[index] = Float16(velocity.x)
                    values[index + 1] = Float16(velocity.y)
                    values[index + 2] = Float16(velocity.z)
                }
            }
        }
        write(values, to: texture, components: 4)
    }

    func allValuesAreFinite(texture: MTLTexture, components: Int) -> Bool {
        readValues(texture: texture, components: components).allSatisfy { Float($0).isFinite }
    }

    func maximumAbsoluteValue(texture: MTLTexture, components: Int) -> Float {
        readValues(texture: texture, components: components).lazy.map { abs(Float($0)) }.max() ?? 0
    }

    func project(iterations: Int) throws {
        clearPressureTextures()
        guard let commandBuffer = context.queue.makeCommandBuffer() else {
            throw MetalHarnessError.commandEncoding
        }
        try encodeDivergence(commandBuffer: commandBuffer)
        for _ in 0..<iterations {
            try encodeJacobi(commandBuffer: commandBuffer)
            pressureIndex = 1 - pressureIndex
        }
        try encodeProjection(commandBuffer: commandBuffer)
        try commitAndWait(commandBuffer)
        velocityIndex = 1 - velocityIndex
    }

    private static func pipeline(
        named name: String,
        context: MetalContext
    ) throws -> MTLComputePipelineState {
        guard let function = context.library.makeFunction(name: name) else {
            throw MetalHarnessError.missingPipeline(name)
        }
        return try context.device.makeComputePipelineState(function: function)
    }

    private static func texture(
        context: MetalContext,
        format: MTLPixelFormat,
        axis: Int
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = format
        descriptor.width = axis
        descriptor.height = axis
        descriptor.depth = axis
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let texture = context.device.makeTexture(descriptor: descriptor) else {
            throw MetalHarnessError.resourceAllocation("\(format)")
        }
        return texture
    }

    private func encodeDivergence(
        commandBuffer: MTLCommandBuffer,
        velocity: MTLTexture? = nil
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalHarnessError.commandEncoding
        }
        encoder.setComputePipelineState(computeDivergencePipeline)
        encoder.setTexture(velocity ?? velocityTextures[velocityIndex], index: 0)
        encoder.setTexture(divergenceTexture, index: 1)
        setUniforms(on: encoder)
        dispatch(encoder: encoder, pipeline: computeDivergencePipeline)
        encoder.endEncoding()
    }

    private func encodeJacobi(commandBuffer: MTLCommandBuffer) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalHarnessError.commandEncoding
        }
        encoder.setComputePipelineState(jacobiPressurePipeline)
        encoder.setTexture(pressureTextures[pressureIndex], index: 0)
        encoder.setTexture(divergenceTexture, index: 1)
        encoder.setTexture(pressureTextures[1 - pressureIndex], index: 2)
        setUniforms(on: encoder)
        dispatch(encoder: encoder, pipeline: jacobiPressurePipeline)
        encoder.endEncoding()
    }

    private func encodeProjection(commandBuffer: MTLCommandBuffer) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalHarnessError.commandEncoding
        }
        encoder.setComputePipelineState(subtractPressureGradientPipeline)
        encoder.setTexture(velocityTextures[velocityIndex], index: 0)
        encoder.setTexture(pressureTextures[pressureIndex], index: 1)
        encoder.setTexture(velocityTextures[1 - velocityIndex], index: 2)
        setUniforms(on: encoder)
        dispatch(encoder: encoder, pipeline: subtractPressureGradientPipeline)
        encoder.endEncoding()
    }

    private func setUniforms(on encoder: MTLComputeCommandEncoder, index: Int = 0) {
        var uniforms = uniforms
        encoder.setBytes(&uniforms, length: MemoryLayout<GPUUniforms>.stride, index: index)
    }

    private func dispatchParticles(
        encoder: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState
    ) {
        let width = min(pipeline.threadExecutionWidth, pipeline.maxTotalThreadsPerThreadgroup)
        encoder.dispatchThreads(
            MTLSize(width: particleCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
    }

    private func dispatch(
        encoder: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState
    ) {
        let width = min(4, pipeline.threadExecutionWidth)
        let height = min(4, pipeline.maxTotalThreadsPerThreadgroup / width)
        let depth = min(4, pipeline.maxTotalThreadsPerThreadgroup / (width * height))
        encoder.dispatchThreads(
            MTLSize(width: gridAxis, height: gridAxis, depth: gridAxis),
            threadsPerThreadgroup: MTLSize(width: width, height: height, depth: depth)
        )
    }

    private func clearPressureTextures() {
        let values = [Float16](repeating: 0, count: gridAxis * gridAxis * gridAxis)
        for texture in pressureTextures {
            write(values, to: texture, components: 1)
        }
    }

    private func write(_ values: [Float16], to texture: MTLTexture, components: Int) {
        values.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, gridAxis, gridAxis, gridAxis),
                mipmapLevel: 0,
                slice: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: gridAxis * components * MemoryLayout<Float16>.stride,
                bytesPerImage: gridAxis * gridAxis * components * MemoryLayout<Float16>.stride
            )
        }
    }

    private func read(texture: MTLTexture, into values: inout [Float16], components: Int) {
        values.withUnsafeMutableBytes { bytes in
            texture.getBytes(
                bytes.baseAddress!,
                bytesPerRow: gridAxis * components * MemoryLayout<Float16>.stride,
                bytesPerImage: gridAxis * gridAxis * components * MemoryLayout<Float16>.stride,
                from: MTLRegionMake3D(0, 0, 0, gridAxis, gridAxis, gridAxis),
                mipmapLevel: 0,
                slice: 0
            )
        }
    }

    private func readValues(texture: MTLTexture, components: Int) -> [Float16] {
        var values = [Float16](
            repeating: 0,
            count: gridAxis * gridAxis * gridAxis * components
        )
        read(texture: texture, into: &values, components: components)
        return values
    }

    private func commitAndWait(_ commandBuffer: MTLCommandBuffer) throws {
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw MetalHarnessError.commandFailure(commandBuffer.error)
        }
    }
}
