import Metal
import NebulaForgeCore

typealias PostProcessTextureFactory = (MTLTextureDescriptor) -> MTLTexture?

struct PostProcessTargetKey: Equatable {
    let sourceWidth: Int
    let sourceHeight: Int
    let destinationWidth: Int
    let destinationHeight: Int

    var bloomWidth: Int {
        sourceWidth > 0 ? max((sourceWidth + 1) / 2, 1) : 0
    }

    var bloomHeight: Int {
        sourceHeight > 0 ? max((sourceHeight + 1) / 2, 1) : 0
    }

    init(
        sourceWidth: Int,
        sourceHeight: Int,
        destinationWidth: Int,
        destinationHeight: Int
    ) {
        self.sourceWidth = max(sourceWidth, 0)
        self.sourceHeight = max(sourceHeight, 0)
        self.destinationWidth = max(destinationWidth, 0)
        self.destinationHeight = max(destinationHeight, 0)
    }
}

struct PostProcessUniforms {
    var sourceAndBloomSize: SIMD4<UInt32>
    var destinationAndBlur: SIMD4<UInt32>
    var appearance: SIMD4<Float>
    var backgroundAndPadding: SIMD4<Float>

    init(key: PostProcessTargetKey, parameters: SimulationParameters) {
        let parameters = parameters.validated()
        sourceAndBloomSize = SIMD4(
            UInt32(key.sourceWidth),
            UInt32(key.sourceHeight),
            UInt32(key.bloomWidth),
            UInt32(key.bloomHeight)
        )
        destinationAndBlur = SIMD4(
            UInt32(key.destinationWidth),
            UInt32(key.destinationHeight),
            UInt32((parameters.bloomRadius * 0.5).rounded()),
            0
        )
        appearance = SIMD4(
            parameters.trailPersistence,
            parameters.bloomIntensity,
            parameters.depthFog,
            parameters.exposure
        )
        backgroundAndPadding = SIMD4(
            parameters.backgroundIntensity,
            0,
            0,
            0
        )
    }
}

private struct PostProcessResources {
    let key: PostProcessTargetKey
    let trails: [MTLTexture]
    let bloom: [MTLTexture]
}

final class PostProcessor {
    private let storageMode: MTLStorageMode
    private let textureFactory: PostProcessTextureFactory
    private let clearPipeline: MTLComputePipelineState
    private let accumulateTrailsPipeline: MTLComputePipelineState
    private let extractBloomPipeline: MTLComputePipelineState
    private let blurHorizontalPipeline: MTLComputePipelineState
    private let blurVerticalPipeline: MTLComputePipelineState
    private let compositeToneMapPipeline: MTLComputePipelineState
    private let temporalStateLock = NSLock()

    private var resources: PostProcessResources?
    private var trailReadIndex = 0
    private var resetGeneration: UInt64 = 1
    private var clearedGeneration: UInt64 = 0

    var trailTextures: [MTLTexture] {
        resources?.trails ?? []
    }

    var bloomTextures: [MTLTexture] {
        resources?.bloom ?? []
    }

    var isTemporalResetPending: Bool {
        temporalStateLock.lock()
        defer { temporalStateLock.unlock() }
        return resetGeneration != clearedGeneration
    }

    convenience init(context: MetalContext) throws {
        try self.init(context: context, storageMode: .private)
    }

    init(
        context: MetalContext,
        storageMode: MTLStorageMode,
        textureFactory: PostProcessTextureFactory? = nil
    ) throws {
        self.storageMode = storageMode
        self.textureFactory = textureFactory ?? { descriptor in
            context.device.makeTexture(descriptor: descriptor)
        }
        clearPipeline = try Self.pipeline(named: "clearPostProcessTexture", context: context)
        accumulateTrailsPipeline = try Self.pipeline(named: "accumulateTrails", context: context)
        extractBloomPipeline = try Self.pipeline(named: "extractBloom", context: context)
        blurHorizontalPipeline = try Self.pipeline(named: "blurHorizontal", context: context)
        blurVerticalPipeline = try Self.pipeline(named: "blurVertical", context: context)
        compositeToneMapPipeline = try Self.pipeline(named: "compositeToneMap", context: context)
    }

    func resetTemporalHistory() {
        temporalStateLock.lock()
        resetGeneration &+= 1
        temporalStateLock.unlock()
    }

    func encode(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        depth: MTLTexture,
        destination: MTLTexture,
        parameters: SimulationParameters
    ) throws {
        guard
            source.width > 0,
            source.height > 0,
            depth.width == source.width,
            depth.height == source.height,
            destination.width > 0,
            destination.height > 0
        else {
            throw RendererError.commandEncoding("post-process texture dimensions")
        }

        let key = PostProcessTargetKey(
            sourceWidth: source.width,
            sourceHeight: source.height,
            destinationWidth: destination.width,
            destinationHeight: destination.height
        )
        try ensureResources(for: key)
        guard let resources else {
            throw RendererError.commandEncoding("post-process resources")
        }

        var uniforms = PostProcessUniforms(key: key, parameters: parameters)
        let generation = resetSnapshot()
        let needsClear = generation != clearedGenerationSnapshot()
        if needsClear {
            try encodeClear(commandBuffer: commandBuffer, texture: resources.trails[0])
            try encodeClear(commandBuffer: commandBuffer, texture: resources.trails[1])
        }

        let outputTrailIndex = 1 - trailReadIndex
        try encodePass(
            commandBuffer: commandBuffer,
            pipeline: accumulateTrailsPipeline,
            label: "Accumulate Temporal Trails",
            textures: [
                (source, 0),
                (resources.trails[trailReadIndex], 1),
                (resources.trails[outputTrailIndex], 2),
            ],
            uniforms: &uniforms,
            outputSize: MTLSize(width: key.sourceWidth, height: key.sourceHeight, depth: 1)
        )
        try encodePass(
            commandBuffer: commandBuffer,
            pipeline: extractBloomPipeline,
            label: "Extract HDR Bloom",
            textures: [
                (resources.trails[outputTrailIndex], 0),
                (resources.bloom[0], 1),
            ],
            uniforms: &uniforms,
            outputSize: MTLSize(width: key.bloomWidth, height: key.bloomHeight, depth: 1)
        )
        try encodePass(
            commandBuffer: commandBuffer,
            pipeline: blurHorizontalPipeline,
            label: "Blur Bloom Horizontally",
            textures: [
                (resources.bloom[0], 0),
                (resources.bloom[1], 1),
            ],
            uniforms: &uniforms,
            outputSize: MTLSize(width: key.bloomWidth, height: key.bloomHeight, depth: 1)
        )
        try encodePass(
            commandBuffer: commandBuffer,
            pipeline: blurVerticalPipeline,
            label: "Blur Bloom Vertically",
            textures: [
                (resources.bloom[1], 0),
                (resources.bloom[0], 1),
            ],
            uniforms: &uniforms,
            outputSize: MTLSize(width: key.bloomWidth, height: key.bloomHeight, depth: 1)
        )
        try encodePass(
            commandBuffer: commandBuffer,
            pipeline: compositeToneMapPipeline,
            label: "Composite Fog Bloom and Tone Map",
            textures: [
                (resources.trails[outputTrailIndex], 0),
                (resources.bloom[0], 1),
                (depth, 2),
                (destination, 3),
            ],
            uniforms: &uniforms,
            outputSize: MTLSize(
                width: key.destinationWidth,
                height: key.destinationHeight,
                depth: 1
            )
        )

        trailReadIndex = outputTrailIndex
        if needsClear {
            markCleared(generation: generation)
        }
    }

    static func trailTextureDescriptor(
        for key: PostProcessTargetKey,
        storageMode: MTLStorageMode
    ) -> MTLTextureDescriptor {
        textureDescriptor(
            width: key.sourceWidth,
            height: key.sourceHeight,
            storageMode: storageMode
        )
    }

    static func bloomTextureDescriptor(
        for key: PostProcessTargetKey,
        storageMode: MTLStorageMode
    ) -> MTLTextureDescriptor {
        textureDescriptor(
            width: key.bloomWidth,
            height: key.bloomHeight,
            storageMode: storageMode
        )
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
            throw RendererError.pipeline(
                "\(name) compute pipeline: \(error.localizedDescription)"
            )
        }
    }

    private static func textureDescriptor(
        width: Int,
        height: Int,
        storageMode: MTLStorageMode
    ) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = storageMode
        descriptor.usage = [.shaderRead, .shaderWrite]
        return descriptor
    }

    private func ensureResources(for key: PostProcessTargetKey) throws {
        guard resources?.key != key else { return }

        let trailDescriptor = Self.trailTextureDescriptor(
            for: key,
            storageMode: storageMode
        )
        let bloomDescriptor = Self.bloomTextureDescriptor(
            for: key,
            storageMode: storageMode
        )
        guard let trailA = textureFactory(trailDescriptor) else {
            throw RendererError.pipeline("trail texture A allocation")
        }
        guard let trailB = textureFactory(trailDescriptor) else {
            throw RendererError.pipeline("trail texture B allocation")
        }
        guard let bloomA = textureFactory(bloomDescriptor) else {
            throw RendererError.pipeline("bloom texture A allocation")
        }
        guard let bloomB = textureFactory(bloomDescriptor) else {
            throw RendererError.pipeline("bloom texture B allocation")
        }
        trailA.label = "Temporal Trail A"
        trailB.label = "Temporal Trail B"
        bloomA.label = "Half Resolution Bloom A"
        bloomB.label = "Half Resolution Bloom B"

        resources = PostProcessResources(
            key: key,
            trails: [trailA, trailB],
            bloom: [bloomA, bloomB]
        )
        trailReadIndex = 0
        resetTemporalHistory()
    }

    private func encodeClear(
        commandBuffer: MTLCommandBuffer,
        texture: MTLTexture
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RendererError.commandEncoding("clear temporal trail")
        }
        encoder.label = "Clear Temporal Trail"
        encoder.setComputePipelineState(clearPipeline)
        encoder.setTexture(texture, index: 0)
        dispatch(
            encoder: encoder,
            pipeline: clearPipeline,
            size: MTLSize(width: texture.width, height: texture.height, depth: 1)
        )
        encoder.endEncoding()
    }

    private func encodePass(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLComputePipelineState,
        label: String,
        textures: [(MTLTexture, Int)],
        uniforms: inout PostProcessUniforms,
        outputSize: MTLSize
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RendererError.commandEncoding(label)
        }
        encoder.label = label
        encoder.setComputePipelineState(pipeline)
        for (texture, index) in textures {
            encoder.setTexture(texture, index: index)
        }
        encoder.setBytes(
            &uniforms,
            length: MemoryLayout<PostProcessUniforms>.stride,
            index: 0
        )
        dispatch(encoder: encoder, pipeline: pipeline, size: outputSize)
        encoder.endEncoding()
    }

    private func dispatch(
        encoder: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState,
        size: MTLSize
    ) {
        let width = min(16, pipeline.threadExecutionWidth)
        let height = max(
            1,
            min(16, pipeline.maxTotalThreadsPerThreadgroup / max(width, 1))
        )
        encoder.dispatchThreads(
            size,
            threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1)
        )
    }

    private func resetSnapshot() -> UInt64 {
        temporalStateLock.lock()
        defer { temporalStateLock.unlock() }
        return resetGeneration
    }

    private func clearedGenerationSnapshot() -> UInt64 {
        temporalStateLock.lock()
        defer { temporalStateLock.unlock() }
        return clearedGeneration
    }

    private func markCleared(generation: UInt64) {
        temporalStateLock.lock()
        if resetGeneration == generation {
            clearedGeneration = generation
        }
        temporalStateLock.unlock()
    }
}
