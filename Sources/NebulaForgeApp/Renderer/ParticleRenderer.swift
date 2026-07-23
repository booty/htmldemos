import CoreGraphics
import Metal
import simd

struct ParticleRenderTargetKey: Equatable {
    let drawableSize: CGSize
    let renderScale: Float
    let width: Int
    let height: Int

    init(drawableSize: CGSize, renderScale: Float) {
        let finiteScale = renderScale.isFinite ? max(renderScale, 0) : 0
        let finiteWidth = drawableSize.width.isFinite ? max(drawableSize.width, 0) : 0
        let finiteHeight = drawableSize.height.isFinite ? max(drawableSize.height, 0) : 0

        self.drawableSize = CGSize(width: finiteWidth, height: finiteHeight)
        self.renderScale = finiteScale
        width = Int((finiteWidth * CGFloat(finiteScale)).rounded())
        height = Int((finiteHeight * CGFloat(finiteScale)).rounded())
    }
}

struct ParticleRenderFrameState {
    var viewProjection: simd_float4x4
    var activeParticleCount: Int
    var particleSize: Float
    var paletteIndex: UInt32
    var velocityColorMix: Float

    static let empty = ParticleRenderFrameState(
        viewProjection: matrix_identity_float4x4,
        activeParticleCount: 0,
        particleSize: 1,
        paletteIndex: 0,
        velocityColorMix: 0
    )
}

final class ParticleRenderer {
    private let device: MTLDevice
    private let particleBuffer: MTLBuffer
    private let particlePipeline: MTLRenderPipelineState
    private let displayPipeline: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState
    private var renderTargetKey: ParticleRenderTargetKey?

    private(set) var hdrTexture: MTLTexture?
    private(set) var depthTexture: MTLTexture?
    var frameState = ParticleRenderFrameState.empty

    init(
        context: MetalContext,
        particleBuffer: MTLBuffer,
        destinationPixelFormat: MTLPixelFormat
    ) throws {
        device = context.device
        self.particleBuffer = particleBuffer

        do {
            particlePipeline = try context.device.makeRenderPipelineState(
                descriptor: Self.particlePipelineDescriptor(library: context.library)
            )
            displayPipeline = try context.device.makeRenderPipelineState(
                descriptor: Self.displayPipelineDescriptor(
                    library: context.library,
                    destinationPixelFormat: destinationPixelFormat
                )
            )
        } catch let error as RendererError {
            throw error
        } catch {
            throw RendererError.pipeline(
                "particle render pipeline: \(error.localizedDescription)"
            )
        }

        guard let depthStencilState = context.device.makeDepthStencilState(
            descriptor: Self.depthStencilDescriptor()
        ) else {
            throw RendererError.pipeline("particle depth stencil state")
        }
        self.depthStencilState = depthStencilState
    }

    func encode(
        commandBuffer: MTLCommandBuffer,
        drawableSize: CGSize,
        renderScale: Float
    ) throws {
        let key = ParticleRenderTargetKey(
            drawableSize: drawableSize,
            renderScale: renderScale
        )
        guard key.width > 0, key.height > 0 else {
            hdrTexture = nil
            depthTexture = nil
            renderTargetKey = key
            return
        }
        try ensureRenderTargets(for: key)
        guard let hdrTexture, let depthTexture else {
            throw RendererError.commandEncoding("particle render targets")
        }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = hdrTexture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 0
        )
        descriptor.depthAttachment.texture = depthTexture
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .store
        descriptor.depthAttachment.clearDepth = 1

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw RendererError.commandEncoding("HDR particle pass")
        }
        encoder.label = "HDR Particle Streaks"
        encoder.setRenderPipelineState(particlePipeline)
        encoder.setDepthStencilState(depthStencilState)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)

        let capacity = particleBuffer.length / MemoryLayout<GPUParticle>.stride
        let activeParticleCount = min(max(frameState.activeParticleCount, 0), capacity)
        var uniforms = ParticleRenderUniforms(
            viewProjection: frameState.viewProjection,
            viewportAndSize: SIMD4(
                Float(key.width),
                Float(key.height),
                max(frameState.particleSize, 0.25) * key.renderScale,
                min(max(frameState.velocityColorMix, 0), 1)
            ),
            paletteAndCount: SIMD4(
                min(frameState.paletteIndex, 3),
                UInt32(activeParticleCount),
                0,
                0
            )
        )
        encoder.setVertexBytes(
            &uniforms,
            length: MemoryLayout<ParticleRenderUniforms>.stride,
            index: 1
        )
        if activeParticleCount > 0 {
            encoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4,
                instanceCount: activeParticleCount
            )
        }
        encoder.endEncoding()
    }

    func encodeDisplay(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor
    ) throws {
        guard let hdrTexture else { return }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor
        ) else {
            throw RendererError.commandEncoding("particle display pass")
        }
        encoder.label = "Temporary HDR Display Composite"
        encoder.setRenderPipelineState(displayPipeline)
        encoder.setFragmentTexture(hdrTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    static func hdrTextureDescriptor(
        for key: ParticleRenderTargetKey
    ) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: key.width,
            height: key.height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        return descriptor
    }

    static func depthTextureDescriptor(
        for key: ParticleRenderTargetKey
    ) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: key.width,
            height: key.height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        return descriptor
    }

    static func particlePipelineDescriptor(
        library: MTLLibrary
    ) throws -> MTLRenderPipelineDescriptor {
        guard let vertex = library.makeFunction(name: "particleVertex") else {
            throw RendererError.pipeline("particle vertex function")
        }
        guard let fragment = library.makeFunction(name: "particleFragment") else {
            throw RendererError.pipeline("particle fragment function")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "HDR Particle Streaks"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        descriptor.depthAttachmentPixelFormat = .depth32Float
        let color = descriptor.colorAttachments[0]!
        color.isBlendingEnabled = true
        color.rgbBlendOperation = .add
        color.alphaBlendOperation = .add
        color.sourceRGBBlendFactor = .one
        color.destinationRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .one
        return descriptor
    }

    static func depthStencilDescriptor() -> MTLDepthStencilDescriptor {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.label = "Particle Depth"
        descriptor.depthCompareFunction = .lessEqual
        descriptor.isDepthWriteEnabled = true
        return descriptor
    }

    private static func displayPipelineDescriptor(
        library: MTLLibrary,
        destinationPixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineDescriptor {
        guard let vertex = library.makeFunction(name: "fullscreenVertex") else {
            throw RendererError.pipeline("particle display vertex function")
        }
        guard let fragment = library.makeFunction(name: "particleDisplayFragment") else {
            throw RendererError.pipeline("particle display fragment function")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Temporary HDR Display Composite"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = destinationPixelFormat
        return descriptor
    }

    private func ensureRenderTargets(for key: ParticleRenderTargetKey) throws {
        guard key != renderTargetKey else { return }

        guard let newHDRTexture = device.makeTexture(
            descriptor: Self.hdrTextureDescriptor(for: key)
        ) else {
            throw RendererError.pipeline("HDR particle texture allocation")
        }
        newHDRTexture.label = "Particle HDR Color"
        guard let newDepthTexture = device.makeTexture(
            descriptor: Self.depthTextureDescriptor(for: key)
        ) else {
            throw RendererError.pipeline("particle depth texture allocation")
        }
        newDepthTexture.label = "Particle Depth"

        hdrTexture = newHDRTexture
        depthTexture = newDepthTexture
        renderTargetKey = key
    }
}
