import Metal
import NebulaForgeCore
import XCTest
@testable import NebulaForgeApp

final class PostProcessorTests: XCTestCase {
    func testTargetDescriptorsUseFullResolutionTrailsAndCeilHalfResolutionBloom() {
        let key = PostProcessTargetKey(
            sourceWidth: 65,
            sourceHeight: 47,
            destinationWidth: 130,
            destinationHeight: 94
        )

        let trail = PostProcessor.trailTextureDescriptor(for: key, storageMode: .private)
        let bloom = PostProcessor.bloomTextureDescriptor(for: key, storageMode: .private)

        XCTAssertEqual(trail.width, 65)
        XCTAssertEqual(trail.height, 47)
        XCTAssertEqual(trail.pixelFormat, .rgba16Float)
        XCTAssertEqual(trail.storageMode, .private)
        XCTAssertTrue(trail.usage.contains(.shaderRead))
        XCTAssertTrue(trail.usage.contains(.shaderWrite))

        XCTAssertEqual(bloom.width, 33)
        XCTAssertEqual(bloom.height, 24)
        XCTAssertEqual(bloom.pixelFormat, .rgba16Float)
        XCTAssertEqual(bloom.storageMode, .private)
        XCTAssertTrue(bloom.usage.contains(.shaderRead))
        XCTAssertTrue(bloom.usage.contains(.shaderWrite))
    }

    func testAppearanceUniformsPreserveValidatedBoundaries() {
        var minimum = SimulationParameters.default
        minimum.trailPersistence = 0
        minimum.bloomIntensity = 0
        minimum.bloomRadius = 0
        minimum.depthFog = 0
        minimum.exposure = -4
        minimum.backgroundIntensity = 0

        var maximum = SimulationParameters.default
        maximum.trailPersistence = 0.98
        maximum.bloomIntensity = 3
        maximum.bloomRadius = 24
        maximum.depthFog = 1
        maximum.exposure = 4
        maximum.backgroundIntensity = 0.4

        let key = PostProcessTargetKey(
            sourceWidth: 64,
            sourceHeight: 48,
            destinationWidth: 128,
            destinationHeight: 96
        )
        let low = PostProcessUniforms(key: key, parameters: minimum)
        let high = PostProcessUniforms(key: key, parameters: maximum)

        XCTAssertEqual(low.appearance, SIMD4(0, 0, 0, -4))
        XCTAssertEqual(low.backgroundAndPadding.x, 0)
        XCTAssertEqual(low.destinationAndBlur.z, 0)

        XCTAssertEqual(high.appearance, SIMD4(0.98, 3, 1, 4))
        XCTAssertEqual(high.backgroundAndPadding.x, 0.4)
        XCTAssertEqual(high.destinationAndBlur.z, 12)
    }

    func testResourcesAreReusedAndDestinationResizeReplacesAllTargets() throws {
        let harness = try PostProcessTestHarness(width: 8, height: 6)
        try harness.encode()
        let firstTrails = harness.processor.trailTextures
        let firstBloom = harness.processor.bloomTextures

        try harness.encode()
        XCTAssertTrue(firstTrails[0] === harness.processor.trailTextures[0])
        XCTAssertTrue(firstTrails[1] === harness.processor.trailTextures[1])
        XCTAssertTrue(firstBloom[0] === harness.processor.bloomTextures[0])
        XCTAssertTrue(firstBloom[1] === harness.processor.bloomTextures[1])

        harness.replaceDestination(width: 9, height: 6)
        try harness.encode()
        XCTAssertFalse(firstTrails[0] === harness.processor.trailTextures[0])
        XCTAssertFalse(firstTrails[1] === harness.processor.trailTextures[1])
        XCTAssertFalse(firstBloom[0] === harness.processor.bloomTextures[0])
        XCTAssertFalse(firstBloom[1] === harness.processor.bloomTextures[1])
    }

    func testResizeAllocationFailurePreservesPublishedResourceSet() throws {
        let context = try MetalContext()
        let gate = PostProcessTextureAllocationGate(device: context.device)
        let processor = try PostProcessor(
            context: context,
            storageMode: .shared,
            textureFactory: gate.makeTexture
        )
        let harness = try PostProcessTestHarness(
            context: context,
            processor: processor,
            width: 8,
            height: 6
        )
        try harness.encode()
        let firstTrails = processor.trailTextures
        let firstBloom = processor.bloomTextures

        gate.failAfterAdditionalAllocations(2)
        harness.replaceTextures(width: 10, height: 7)
        XCTAssertThrowsError(try harness.encode())

        XCTAssertTrue(firstTrails[0] === processor.trailTextures[0])
        XCTAssertTrue(firstTrails[1] === processor.trailTextures[1])
        XCTAssertTrue(firstBloom[0] === processor.bloomTextures[0])
        XCTAssertTrue(firstBloom[1] === processor.bloomTextures[1])
    }

    func testExplicitTemporalResetClearsBothTrailTextures() throws {
        let harness = try PostProcessTestHarness(width: 8, height: 6)
        harness.parameters.trailPersistence = 0.98
        harness.parameters.bloomIntensity = 0
        harness.parameters.depthFog = 0
        harness.parameters.backgroundIntensity = 0
        harness.fillSource(SIMD4<Float16>(4, 1, 0.5, 1))
        try harness.encode()
        XCTAssertTrue(harness.processor.trailTextures.contains {
            harness.maximumRGB(in: $0) > 0
        })

        harness.fillSource(.zero)
        harness.processor.resetTemporalHistory()
        XCTAssertTrue(harness.processor.isTemporalResetPending)
        try harness.encode()

        XCTAssertFalse(harness.processor.isTemporalResetPending)
        for texture in harness.processor.trailTextures {
            XCTAssertEqual(harness.maximumRGB(in: texture), 0, accuracy: 0.000_01)
        }
        XCTAssertEqual(harness.maximumRGB(in: harness.destination), 0, accuracy: 0.000_01)
    }

    func testStationaryHDRDoesNotGainEnergyFromTrailHistory() throws {
        let harness = try PostProcessTestHarness(width: 8, height: 6)
        harness.parameters.trailPersistence = 0.98
        harness.parameters.bloomIntensity = 0
        harness.parameters.depthFog = 0
        harness.parameters.backgroundIntensity = 0
        harness.fillSource(SIMD4<Float16>(1, 0.5, 0.25, 1))

        try harness.encode()
        let firstFrameMaximum = harness.processor.trailTextures
            .map(harness.maximumRGB)
            .max() ?? 0
        try harness.encode()
        let secondFrameMaximum = harness.processor.trailTextures
            .map(harness.maximumRGB)
            .max() ?? 0

        XCTAssertEqual(secondFrameMaximum, firstFrameMaximum, accuracy: 0.001)
    }

    func testResizeStartsWithNoStaleHistory() throws {
        let harness = try PostProcessTestHarness(width: 8, height: 6)
        harness.parameters.trailPersistence = 0.98
        harness.parameters.bloomIntensity = 0
        harness.parameters.depthFog = 0
        harness.parameters.backgroundIntensity = 0
        harness.fillSource(SIMD4<Float16>(2, 0, 0, 1))
        try harness.encode()
        XCTAssertGreaterThan(harness.maximumRGB(in: harness.destination), 0)

        harness.replaceTextures(width: 11, height: 7)
        harness.fillSource(.zero)
        try harness.encode()

        XCTAssertEqual(harness.maximumRGB(in: harness.destination), 0, accuracy: 0.000_01)
        for texture in harness.processor.trailTextures {
            XCTAssertEqual(harness.maximumRGB(in: texture), 0, accuracy: 0.000_01)
        }
    }

    func testBoundaryAppearanceValuesProduceFiniteToneMappedOutput() throws {
        let harness = try PostProcessTestHarness(width: 8, height: 6)
        harness.fillSource(SIMD4<Float16>(60_000, 30_000, 1_000, 1))
        let boundaries: [(Float, Float, Float, Float, Float, Float)] = [
            (0, 0, 0, 0, -4, 0),
            (0.98, 3, 24, 1, 4, 0.4),
        ]

        for (trail, bloom, radius, fog, exposure, background) in boundaries {
            harness.parameters.trailPersistence = trail
            harness.parameters.bloomIntensity = bloom
            harness.parameters.bloomRadius = radius
            harness.parameters.depthFog = fog
            harness.parameters.exposure = exposure
            harness.parameters.backgroundIntensity = background
            harness.processor.resetTemporalHistory()
            try harness.encode()

            let output = harness.readRGBA16(from: harness.destination)
            XCTAssertTrue(output.allSatisfy { Float($0).isFinite })
            XCTAssertTrue(output.allSatisfy { $0 >= 0 && $0 <= 1 })
        }
    }

    func testCompositeWritesSRGBDrawableTexture() throws {
        let harness = try PostProcessTestHarness(width: 8, height: 6)
        harness.replaceDestination(
            width: 13,
            height: 9,
            pixelFormat: .bgra8Unorm_srgb
        )
        harness.parameters.trailPersistence = 0
        harness.parameters.bloomIntensity = 0
        harness.parameters.depthFog = 0
        harness.parameters.backgroundIntensity = 0
        harness.fillSource(SIMD4<Float16>(2, 0.5, 0.25, 1))

        try harness.encode()

        let output = harness.readBGRA8(from: harness.destination)
        XCTAssertTrue(output.enumerated().allSatisfy { index, value in
            index % 4 != 3 || value == 255
        })
        XCTAssertTrue(stride(from: 0, to: output.count, by: 4).contains { pixel in
            output[pixel] > 0 || output[pixel + 1] > 0 || output[pixel + 2] > 0
        })
    }
}

private final class PostProcessTextureAllocationGate {
    private let device: MTLDevice
    private var remainingSuccessfulAllocations: Int?

    init(device: MTLDevice) {
        self.device = device
    }

    func failAfterAdditionalAllocations(_ count: Int) {
        remainingSuccessfulAllocations = count
    }

    func makeTexture(descriptor: MTLTextureDescriptor) -> MTLTexture? {
        if let remainingSuccessfulAllocations {
            guard remainingSuccessfulAllocations > 0 else { return nil }
            self.remainingSuccessfulAllocations = remainingSuccessfulAllocations - 1
        }
        return device.makeTexture(descriptor: descriptor)
    }
}

private final class PostProcessTestHarness {
    let context: MetalContext
    let processor: PostProcessor
    var source: MTLTexture
    var depth: MTLTexture
    var destination: MTLTexture
    var parameters = SimulationParameters.default

    convenience init(width: Int, height: Int) throws {
        let context = try MetalContext()
        let processor = try PostProcessor(context: context, storageMode: .shared)
        try self.init(
            context: context,
            processor: processor,
            width: width,
            height: height
        )
    }

    init(
        context: MetalContext,
        processor: PostProcessor,
        width: Int,
        height: Int
    ) throws {
        self.context = context
        self.processor = processor
        source = try Self.makeTexture(
            device: context.device,
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            usage: [.shaderRead]
        )
        depth = try Self.makeTexture(
            device: context.device,
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            usage: [.shaderRead]
        )
        destination = try Self.makeTexture(
            device: context.device,
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            usage: [.shaderWrite]
        )
        fillDepth(1)
        fillSource(.zero)
    }

    func replaceTextures(width: Int, height: Int) {
        source = try! Self.makeTexture(
            device: context.device,
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            usage: [.shaderRead]
        )
        depth = try! Self.makeTexture(
            device: context.device,
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            usage: [.shaderRead]
        )
        replaceDestination(width: width, height: height)
        fillDepth(1)
    }

    func replaceDestination(
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat = .rgba16Float
    ) {
        destination = try! Self.makeTexture(
            device: context.device,
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            usage: [.shaderWrite]
        )
    }

    func encode() throws {
        guard let commandBuffer = context.queue.makeCommandBuffer() else {
            throw RendererError.commandEncoding("post-process test command buffer")
        }
        try processor.encode(
            commandBuffer: commandBuffer,
            source: source,
            depth: depth,
            destination: destination,
            parameters: parameters
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw RendererError.commandEncoding(
                "post-process test: \(commandBuffer.error?.localizedDescription ?? "unknown")"
            )
        }
    }

    func fillSource(_ value: SIMD4<Float16>) {
        let values = Array(repeating: value, count: source.width * source.height)
        values.withUnsafeBytes { bytes in
            source.replace(
                region: MTLRegionMake2D(0, 0, source.width, source.height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: source.width * MemoryLayout<SIMD4<Float16>>.stride
            )
        }
    }

    func fillDepth(_ value: Float) {
        let values = Array(repeating: value, count: depth.width * depth.height)
        values.withUnsafeBytes { bytes in
            depth.replace(
                region: MTLRegionMake2D(0, 0, depth.width, depth.height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: depth.width * MemoryLayout<Float>.stride
            )
        }
    }

    func readRGBA16(from texture: MTLTexture) -> [Float16] {
        var values = Array(
            repeating: Float16.zero,
            count: texture.width * texture.height * 4
        )
        values.withUnsafeMutableBytes { bytes in
            texture.getBytes(
                bytes.baseAddress!,
                bytesPerRow: texture.width * MemoryLayout<SIMD4<Float16>>.stride,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return values
    }

    func readBGRA8(from texture: MTLTexture) -> [UInt8] {
        var values = Array(repeating: UInt8.zero, count: texture.width * texture.height * 4)
        values.withUnsafeMutableBytes { bytes in
            texture.getBytes(
                bytes.baseAddress!,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return values
    }

    func maximumRGB(in texture: MTLTexture) -> Float {
        let values = readRGBA16(from: texture)
        var maximum: Float = 0
        for pixel in stride(from: 0, to: values.count, by: 4) {
            maximum = max(
                maximum,
                Float(values[pixel]),
                Float(values[pixel + 1]),
                Float(values[pixel + 2])
            )
        }
        return maximum
    }

    private static func makeTexture(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat,
        width: Int,
        height: Int,
        usage: MTLTextureUsage
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.pipeline("post-process test texture")
        }
        return texture
    }
}
