import Metal
import NebulaForgeCore

typealias ParticleEncoderFactory = (MTLCommandBuffer) -> MTLComputeCommandEncoder?

final class ParticleSystem {
    static let maximumCapacity = 2_000_000

    let currentBuffer: MTLBuffer

    private let capacity: Int
    private let updateParticlesPipeline: MTLComputePipelineState
    private let updateEncoderFactory: ParticleEncoderFactory

    init(
        context: MetalContext,
        initialParameters: SimulationParameters = .default,
        updateEncoderFactory: ParticleEncoderFactory? = nil
    ) throws {
        capacity = Self.maximumCapacity
        self.updateEncoderFactory = updateEncoderFactory ?? { commandBuffer in
            commandBuffer.makeComputeCommandEncoder()
        }
        let initializeParticlesPipeline = try Self.pipeline(
            named: "initializeParticles",
            context: context
        )
        updateParticlesPipeline = try Self.pipeline(named: "updateParticles", context: context)

        let particleBufferLength = capacity * MemoryLayout<GPUParticle>.stride
        guard let particleBuffer = context.device.makeBuffer(
            length: particleBufferLength,
            options: .storageModePrivate
        ) else {
            throw RendererError.pipeline("particle buffer allocation")
        }
        particleBuffer.label = "Tracer Particles"
        currentBuffer = particleBuffer

        var initialization = SIMD4<UInt32>(0x4e_46_47_31, UInt32(capacity), 0, 0)
        guard let initializationBuffer = context.device.makeBuffer(
            bytes: &initialization,
            length: MemoryLayout<SIMD4<UInt32>>.stride,
            options: .storageModeShared
        ) else {
            throw RendererError.pipeline("particle initialization staging buffer")
        }
        initializationBuffer.label = "Particle Initialization Metadata"

        guard
            let commandBuffer = context.queue.makeCommandBuffer(),
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw RendererError.commandEncoding("particle initialization")
        }
        commandBuffer.label = "Initialize Tracer Particles"
        encoder.label = "Initialize Tracer Particles"
        encoder.setComputePipelineState(initializeParticlesPipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBuffer(initializationBuffer, offset: 0, index: 1)
        var initialUniforms = GPUUniforms(
            parameters: initialParameters,
            schedule: StepSchedule(stepCount: 1, stepDelta: 1.0 / 60.0),
            elapsedTime: 0,
            frameIndex: 0,
            particleCapacity: capacity
        )
        encoder.setBytes(
            &initialUniforms,
            length: MemoryLayout<GPUUniforms>.stride,
            index: 2
        )
        Self.dispatch(
            count: capacity,
            encoder: encoder,
            pipeline: initializeParticlesPipeline
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw RendererError.commandEncoding(
                "particle initialization: \(commandBuffer.error?.localizedDescription ?? "unknown error")"
            )
        }
    }

    func encodeUpdate(
        commandBuffer: MTLCommandBuffer,
        velocityTexture: MTLTexture,
        uniforms: GPUUniforms
    ) throws {
        let activeCount = min(
            Int(uniforms.particleCounts.x),
            Int(uniforms.particleCounts.y),
            capacity
        )
        guard activeCount > 0 else { return }
        guard let encoder = updateEncoderFactory(commandBuffer) else {
            throw RendererError.commandEncoding("particle update")
        }
        encoder.label = "Update Tracer Particles"
        encoder.setComputePipelineState(updateParticlesPipeline)
        encoder.setBuffer(currentBuffer, offset: 0, index: 0)
        encoder.setTexture(velocityTexture, index: 0)
        var uniforms = uniforms
        encoder.setBytes(
            &uniforms,
            length: MemoryLayout<GPUUniforms>.stride,
            index: 1
        )
        Self.dispatch(
            count: activeCount,
            encoder: encoder,
            pipeline: updateParticlesPipeline
        )
        encoder.endEncoding()
    }

    private static func pipeline(
        named name: String,
        context: MetalContext
    ) throws -> MTLComputePipelineState {
        guard let function = context.library.makeFunction(name: name) else {
            throw RendererError.pipeline("\(name) compute function")
        }
        do {
            return try context.device.makeComputePipelineState(function: function)
        } catch {
            throw RendererError.pipeline("\(name) compute pipeline: \(error.localizedDescription)")
        }
    }

    private static func dispatch(
        count: Int,
        encoder: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState
    ) {
        let width = min(
            pipeline.threadExecutionWidth,
            pipeline.maxTotalThreadsPerThreadgroup
        )
        encoder.dispatchThreads(
            MTLSize(width: count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
    }
}
