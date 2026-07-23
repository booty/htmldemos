import CoreGraphics
import Metal
import simd
import XCTest
@testable import NebulaForgeApp

final class ParticleRendererTests: XCTestCase {
    func testRenderTargetKeyUsesDrawablePixelsAndRenderScale() {
        let key = ParticleRenderTargetKey(
            drawableSize: CGSize(width: 1_440, height: 900),
            renderScale: 0.75
        )

        XCTAssertEqual(key.width, 1_080)
        XCTAssertEqual(key.height, 675)
        XCTAssertEqual(key.drawableSize, CGSize(width: 1_440, height: 900))
        XCTAssertEqual(key.renderScale, 0.75)
    }

    func testRenderTargetDescriptorsArePrivateHDRAndDepthTargets() {
        let key = ParticleRenderTargetKey(
            drawableSize: CGSize(width: 320, height: 180),
            renderScale: 0.5
        )

        let hdr = ParticleRenderer.hdrTextureDescriptor(for: key)
        let depth = ParticleRenderer.depthTextureDescriptor(for: key)

        XCTAssertEqual(hdr.width, 160)
        XCTAssertEqual(hdr.height, 90)
        XCTAssertEqual(hdr.pixelFormat, .rgba16Float)
        XCTAssertEqual(hdr.storageMode, .private)
        XCTAssertTrue(hdr.usage.contains(.renderTarget))
        XCTAssertTrue(hdr.usage.contains(.shaderRead))

        XCTAssertEqual(depth.width, 160)
        XCTAssertEqual(depth.height, 90)
        XCTAssertEqual(depth.pixelFormat, .depth32Float)
        XCTAssertEqual(depth.storageMode, .private)
        XCTAssertTrue(depth.usage.contains(.renderTarget))
    }

    func testTargetsAreReusedUntilDrawableSizeOrRenderScaleChanges() throws {
        let harness = try ParticleRenderTestHarness()

        try harness.encode(drawableSize: CGSize(width: 64, height: 48), renderScale: 1)
        let firstHDR = try XCTUnwrap(harness.renderer.hdrTexture)
        let firstDepth = try XCTUnwrap(harness.renderer.depthTexture)

        try harness.encode(drawableSize: CGSize(width: 64, height: 48), renderScale: 1)
        XCTAssertTrue(firstHDR === harness.renderer.hdrTexture)
        XCTAssertTrue(firstDepth === harness.renderer.depthTexture)

        try harness.encode(
            drawableSize: CGSize(width: 64, height: 48),
            renderScale: 0.999
        )
        XCTAssertFalse(firstHDR === harness.renderer.hdrTexture)
        XCTAssertFalse(firstDepth === harness.renderer.depthTexture)
        let scaledHDR = try XCTUnwrap(harness.renderer.hdrTexture)

        try harness.encode(drawableSize: CGSize(width: 65, height: 48), renderScale: 0.999)
        XCTAssertFalse(scaledHDR === harness.renderer.hdrTexture)
    }

    func testParticlePipelineUsesPremultipliedAdditiveBlendAndDepth() throws {
        let context = try MetalContext()
        let descriptor = try ParticleRenderer.particlePipelineDescriptor(
            library: context.library
        )
        let color = try XCTUnwrap(descriptor.colorAttachments[0])
        let depth = ParticleRenderer.depthStencilDescriptor()

        XCTAssertEqual(descriptor.colorAttachments[0].pixelFormat, .rgba16Float)
        XCTAssertEqual(descriptor.depthAttachmentPixelFormat, .depth32Float)
        XCTAssertTrue(color.isBlendingEnabled)
        XCTAssertEqual(color.sourceRGBBlendFactor, .one)
        XCTAssertEqual(color.destinationRGBBlendFactor, .one)
        XCTAssertEqual(color.sourceAlphaBlendFactor, .one)
        XCTAssertEqual(color.destinationAlphaBlendFactor, .one)
        XCTAssertEqual(depth.depthCompareFunction, .lessEqual)
        XCTAssertTrue(depth.isDepthWriteEnabled)
    }

    func testDormantParticleSentinelContributesNoHDRFragments() throws {
        let harness = try ParticleRenderTestHarness()
        harness.setParticle(age: 0.2)
        try harness.encode(drawableSize: CGSize(width: 64, height: 64), renderScale: 1)
        let activeMaximum = try harness.maximumHDRComponent()

        harness.setParticle(age: -1)
        try harness.encode(drawableSize: CGSize(width: 64, height: 64), renderScale: 1)
        let dormantMaximum = try harness.maximumHDRComponent()

        XCTAssertGreaterThan(activeMaximum, 0.1)
        XCTAssertEqual(dormantMaximum, 0, accuracy: 0.000_01)
    }
}

private final class ParticleRenderTestHarness {
    let context: MetalContext
    let renderer: ParticleRenderer

    private let particleBuffer: MTLBuffer

    init() throws {
        context = try MetalContext()
        guard let particleBuffer = context.device.makeBuffer(
            length: MemoryLayout<GPUParticle>.stride,
            options: .storageModeShared
        ) else {
            throw RendererError.pipeline("particle render test buffer")
        }
        self.particleBuffer = particleBuffer
        renderer = try ParticleRenderer(
            context: context,
            particleBuffer: particleBuffer,
            destinationPixelFormat: .bgra8Unorm_srgb
        )
        renderer.frameState = ParticleRenderFrameState(
            viewProjection: matrix_identity_float4x4,
            activeParticleCount: 1,
            particleSize: 8,
            paletteIndex: 0,
            velocityColorMix: 0.75
        )
        setParticle(age: 0.2)
    }

    func setParticle(age: Float) {
        let particle = GPUParticle(
            positionAge: SIMD4(0.05, 0, 0.5, age),
            previousPositionLifetime: SIMD4(-0.05, 0, 0.5, 1),
            velocitySeed: SIMD4(1, 0, 0, 1)
        )
        particleBuffer.contents()
            .assumingMemoryBound(to: GPUParticle.self)
            .pointee = particle
    }

    func encode(drawableSize: CGSize, renderScale: Float) throws {
        guard let commandBuffer = context.queue.makeCommandBuffer() else {
            throw RendererError.commandEncoding("particle render test command buffer")
        }
        try renderer.encode(
            commandBuffer: commandBuffer,
            drawableSize: drawableSize,
            renderScale: renderScale
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw RendererError.commandEncoding(
                "particle render test: \(commandBuffer.error?.localizedDescription ?? "unknown")"
            )
        }
    }

    func maximumHDRComponent() throws -> Float {
        let texture = try XCTUnwrap(renderer.hdrTexture)
        let bytesPerPixel = MemoryLayout<Float16>.stride * 4
        let bytesPerRow = ((texture.width * bytesPerPixel + 255) / 256) * 256
        guard let readback = context.device.makeBuffer(
            length: bytesPerRow * texture.height,
            options: .storageModeShared
        ), let commandBuffer = context.queue.makeCommandBuffer(),
            let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            throw RendererError.commandEncoding("particle HDR readback")
        }
        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: texture.width, height: texture.height, depth: 1),
            to: readback,
            destinationOffset: 0,
            destinationBytesPerRow: bytesPerRow,
            destinationBytesPerImage: bytesPerRow * texture.height
        )
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw RendererError.commandEncoding(
                "particle HDR readback: \(commandBuffer.error?.localizedDescription ?? "unknown")"
            )
        }

        let componentsPerRow = bytesPerRow / MemoryLayout<Float16>.stride
        let values = readback.contents().assumingMemoryBound(to: Float16.self)
        var maximum: Float = 0
        for y in 0..<texture.height {
            for x in 0..<texture.width {
                let start = y * componentsPerRow + x * 4
                for component in 0..<3 {
                    maximum = max(maximum, Float(values[start + component]))
                }
            }
        }
        return maximum
    }
}
