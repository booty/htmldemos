import Metal
import NebulaForgeCore

final class FluidSolver {
    private let device: MTLDevice
    private let storageMode: MTLStorageMode
    private let injectForcesPipeline: MTLComputePipelineState
    private let advectVelocityPipeline: MTLComputePipelineState
    private let applyVorticityPipeline: MTLComputePipelineState
    private let computeDivergencePipeline: MTLComputePipelineState
    private let jacobiPressurePipeline: MTLComputePipelineState
    private let subtractPressureGradientPipeline: MTLComputePipelineState
    private let clearFluidPipeline: MTLComputePipelineState
    private let reduceFiniteDiagnosticPipeline: MTLComputePipelineState

    private var velocityTextures: [MTLTexture] = []
    private var pressureTextures: [MTLTexture] = []
    private var divergenceTexture: MTLTexture!
    private var velocityIndex = 0
    private var pressureIndex = 0
    private var needsClear = true

    private(set) var gridAxis: Int

    var velocityTexture: MTLTexture {
        velocityTextures[velocityIndex]
    }

    init(context: MetalContext, gridAxis: FluidGridAxis) throws {
        device = context.device
        storageMode = .private
        self.gridAxis = gridAxis.rawValue
        injectForcesPipeline = try Self.pipeline(named: "injectForces", context: context)
        advectVelocityPipeline = try Self.pipeline(named: "advectVelocity", context: context)
        applyVorticityPipeline = try Self.pipeline(named: "applyVorticity", context: context)
        computeDivergencePipeline = try Self.pipeline(named: "computeDivergence", context: context)
        jacobiPressurePipeline = try Self.pipeline(named: "jacobiPressure", context: context)
        subtractPressureGradientPipeline = try Self.pipeline(named: "subtractPressureGradient", context: context)
        clearFluidPipeline = try Self.pipeline(named: "clearFluid", context: context)
        reduceFiniteDiagnosticPipeline = try Self.pipeline(named: "reduceFiniteDiagnostic", context: context)
        try allocateTextures(axis: gridAxis.rawValue)
    }

    func resizeIfNeeded(gridAxis: FluidGridAxis) throws {
        guard self.gridAxis != gridAxis.rawValue else { return }
        try allocateTextures(axis: gridAxis.rawValue)
    }

    func encodeStep(
        commandBuffer: MTLCommandBuffer,
        uniforms: GPUUniforms,
        force: InteractionForce
    ) {
        var uniforms = uniforms
        let axis = UInt32(gridAxis)
        uniforms.gridSize = SIMD4(axis, axis, axis, 0)

        if needsClear {
            encodeClear(commandBuffer: commandBuffer, velocity: velocityTextures[0], scalar: pressureTextures[0], uniforms: uniforms)
            encodeClear(commandBuffer: commandBuffer, velocity: velocityTextures[1], scalar: pressureTextures[1], uniforms: uniforms)
            encodeClear(commandBuffer: commandBuffer, velocity: velocityTextures[velocityIndex], scalar: divergenceTexture, uniforms: uniforms)
            needsClear = false
        }

        encodeVelocityPass(
            commandBuffer: commandBuffer,
            pipeline: injectForcesPipeline,
            label: "Inject Fluid Forces",
            uniforms: uniforms,
            force: force
        )
        swapVelocity()

        encodeVelocityPass(
            commandBuffer: commandBuffer,
            pipeline: advectVelocityPipeline,
            label: "Advect Fluid Velocity",
            uniforms: uniforms
        )
        swapVelocity()

        encodeVelocityPass(
            commandBuffer: commandBuffer,
            pipeline: applyVorticityPipeline,
            label: "Apply Vorticity Confinement",
            uniforms: uniforms
        )
        swapVelocity()

        encodeDivergence(commandBuffer: commandBuffer, uniforms: uniforms)

        let iterationCount = min(Int(uniforms.particleCounts.w), 128)
        for _ in 0..<iterationCount {
            encodeJacobi(commandBuffer: commandBuffer, uniforms: uniforms)
            pressureIndex = 1 - pressureIndex
        }

        encodePressureProjection(commandBuffer: commandBuffer, uniforms: uniforms)
        swapVelocity()
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

    private func allocateTextures(axis: Int) throws {
        velocityTextures = try [
            makeTexture(pixelFormat: .rgba16Float, axis: axis, label: "Fluid Velocity A"),
            makeTexture(pixelFormat: .rgba16Float, axis: axis, label: "Fluid Velocity B"),
        ]
        pressureTextures = try [
            makeTexture(pixelFormat: .r16Float, axis: axis, label: "Fluid Pressure A"),
            makeTexture(pixelFormat: .r16Float, axis: axis, label: "Fluid Pressure B"),
        ]
        divergenceTexture = try makeTexture(
            pixelFormat: .r16Float,
            axis: axis,
            label: "Fluid Divergence"
        )
        gridAxis = axis
        velocityIndex = 0
        pressureIndex = 0
        needsClear = true
    }

    private func makeTexture(
        pixelFormat: MTLPixelFormat,
        axis: Int,
        label: String
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = pixelFormat
        descriptor.width = axis
        descriptor.height = axis
        descriptor.depth = axis
        descriptor.mipmapLevelCount = 1
        descriptor.storageMode = storageMode
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.pipeline("\(label) allocation")
        }
        texture.label = label
        return texture
    }

    private func encodeVelocityPass(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLComputePipelineState,
        label: String,
        uniforms: GPUUniforms,
        force: InteractionForce? = nil
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = label
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(velocityTextures[velocityIndex], index: 0)
        encoder.setTexture(velocityTextures[1 - velocityIndex], index: 1)
        set(uniforms, on: encoder, index: 0)
        if var force {
            encoder.setBytes(&force, length: MemoryLayout<InteractionForce>.stride, index: 1)
        }
        dispatch(encoder: encoder, pipeline: pipeline)
        encoder.endEncoding()
    }

    private func encodeDivergence(
        commandBuffer: MTLCommandBuffer,
        uniforms: GPUUniforms
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Compute Fluid Divergence"
        encoder.setComputePipelineState(computeDivergencePipeline)
        encoder.setTexture(velocityTextures[velocityIndex], index: 0)
        encoder.setTexture(divergenceTexture, index: 1)
        set(uniforms, on: encoder, index: 0)
        dispatch(encoder: encoder, pipeline: computeDivergencePipeline)
        encoder.endEncoding()
    }

    private func encodeJacobi(
        commandBuffer: MTLCommandBuffer,
        uniforms: GPUUniforms
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Solve Fluid Pressure"
        encoder.setComputePipelineState(jacobiPressurePipeline)
        encoder.setTexture(pressureTextures[pressureIndex], index: 0)
        encoder.setTexture(divergenceTexture, index: 1)
        encoder.setTexture(pressureTextures[1 - pressureIndex], index: 2)
        set(uniforms, on: encoder, index: 0)
        dispatch(encoder: encoder, pipeline: jacobiPressurePipeline)
        encoder.endEncoding()
    }

    private func encodePressureProjection(
        commandBuffer: MTLCommandBuffer,
        uniforms: GPUUniforms
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Project Fluid Velocity"
        encoder.setComputePipelineState(subtractPressureGradientPipeline)
        encoder.setTexture(velocityTextures[velocityIndex], index: 0)
        encoder.setTexture(pressureTextures[pressureIndex], index: 1)
        encoder.setTexture(velocityTextures[1 - velocityIndex], index: 2)
        set(uniforms, on: encoder, index: 0)
        dispatch(encoder: encoder, pipeline: subtractPressureGradientPipeline)
        encoder.endEncoding()
    }

    private func encodeClear(
        commandBuffer: MTLCommandBuffer,
        velocity: MTLTexture,
        scalar: MTLTexture,
        uniforms: GPUUniforms
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Clear Fluid Resources"
        encoder.setComputePipelineState(clearFluidPipeline)
        encoder.setTexture(velocity, index: 0)
        encoder.setTexture(scalar, index: 1)
        set(uniforms, on: encoder, index: 0)
        dispatch(encoder: encoder, pipeline: clearFluidPipeline)
        encoder.endEncoding()
    }

    private func set(
        _ uniforms: GPUUniforms,
        on encoder: MTLComputeCommandEncoder,
        index: Int
    ) {
        var uniforms = uniforms
        encoder.setBytes(&uniforms, length: MemoryLayout<GPUUniforms>.stride, index: index)
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

    private func swapVelocity() {
        velocityIndex = 1 - velocityIndex
    }
}
