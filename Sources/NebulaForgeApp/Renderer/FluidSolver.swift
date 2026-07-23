import Metal
import NebulaForgeCore

typealias FluidTextureFactory = (MTLTextureDescriptor) -> MTLTexture?
typealias FluidEncoderFactory = (MTLCommandBuffer) -> MTLComputeCommandEncoder?

struct FluidStepState: Equatable {
    var velocityIndex = 0
    var pressureIndex = 0
    var needsClear = true
}

final class FluidSolver {
    private let storageMode: MTLStorageMode
    private let textureFactory: FluidTextureFactory
    private let encoderFactory: FluidEncoderFactory
    private let injectForcesPipeline: MTLComputePipelineState
    private let advectVelocityPipeline: MTLComputePipelineState
    private let applyVorticityPipeline: MTLComputePipelineState
    private let computeDivergencePipeline: MTLComputePipelineState
    private let jacobiPressurePipeline: MTLComputePipelineState
    private let subtractPressureGradientPipeline: MTLComputePipelineState
    private let clearFluidPipeline: MTLComputePipelineState
    private let clearScalarPipeline: MTLComputePipelineState
    private let reduceFiniteDiagnosticPipeline: MTLComputePipelineState

    private var velocityTextures: [MTLTexture] = []
    private var pressureTextures: [MTLTexture] = []
    private var divergenceTexture: MTLTexture!

    private(set) var gridAxis: Int
    private(set) var stepState = FluidStepState()

    var velocityTexture: MTLTexture {
        velocityTextures[stepState.velocityIndex]
    }

    var pressureTexture: MTLTexture {
        pressureTextures[stepState.pressureIndex]
    }

    convenience init(context: MetalContext, gridAxis: FluidGridAxis) throws {
        try self.init(
            context: context,
            gridAxis: gridAxis.rawValue,
            storageMode: .private
        )
    }

    init(
        context: MetalContext,
        gridAxis: Int,
        storageMode: MTLStorageMode,
        textureFactory: FluidTextureFactory? = nil,
        encoderFactory: FluidEncoderFactory? = nil
    ) throws {
        precondition(gridAxis > 0)
        self.storageMode = storageMode
        self.textureFactory = textureFactory ?? { descriptor in
            context.device.makeTexture(descriptor: descriptor)
        }
        self.encoderFactory = encoderFactory ?? { commandBuffer in
            commandBuffer.makeComputeCommandEncoder()
        }
        self.gridAxis = gridAxis
        injectForcesPipeline = try Self.pipeline(named: "injectForces", context: context)
        advectVelocityPipeline = try Self.pipeline(named: "advectVelocity", context: context)
        applyVorticityPipeline = try Self.pipeline(named: "applyVorticity", context: context)
        computeDivergencePipeline = try Self.pipeline(named: "computeDivergence", context: context)
        jacobiPressurePipeline = try Self.pipeline(named: "jacobiPressure", context: context)
        subtractPressureGradientPipeline = try Self.pipeline(named: "subtractPressureGradient", context: context)
        clearFluidPipeline = try Self.pipeline(named: "clearFluid", context: context)
        clearScalarPipeline = try Self.pipeline(named: "clearScalar", context: context)
        reduceFiniteDiagnosticPipeline = try Self.pipeline(named: "reduceFiniteDiagnostic", context: context)
        try allocateTextures(axis: gridAxis)
    }

    func resizeIfNeeded(gridAxis: FluidGridAxis) throws {
        try resizeIfNeeded(gridAxis: gridAxis.rawValue)
    }

    func resizeIfNeeded(gridAxis: Int) throws {
        guard self.gridAxis != gridAxis else { return }
        try allocateTextures(axis: gridAxis)
    }

    func encodeStep(
        commandBuffer: MTLCommandBuffer,
        uniforms: GPUUniforms,
        force: InteractionForce
    ) throws {
        var uniforms = uniforms
        let axis = UInt32(gridAxis)
        uniforms.gridSize = SIMD4(axis, axis, axis, 0)
        var pendingState = stepState

        if pendingState.needsClear {
            try encodeClear(
                commandBuffer: commandBuffer,
                velocity: velocityTextures[0],
                scalar: divergenceTexture,
                uniforms: uniforms
            )
            try encodeClear(
                commandBuffer: commandBuffer,
                velocity: velocityTextures[1],
                scalar: divergenceTexture,
                uniforms: uniforms
            )
            pendingState.needsClear = false
        }

        try encodeVelocityPass(
            commandBuffer: commandBuffer,
            pipeline: injectForcesPipeline,
            label: "Inject Fluid Forces",
            inputIndex: pendingState.velocityIndex,
            uniforms: uniforms,
            force: force
        )
        pendingState.velocityIndex = 1 - pendingState.velocityIndex

        try encodeVelocityPass(
            commandBuffer: commandBuffer,
            pipeline: advectVelocityPipeline,
            label: "Advect Fluid Velocity",
            inputIndex: pendingState.velocityIndex,
            uniforms: uniforms
        )
        pendingState.velocityIndex = 1 - pendingState.velocityIndex

        try encodeVelocityPass(
            commandBuffer: commandBuffer,
            pipeline: applyVorticityPipeline,
            label: "Apply Vorticity Confinement",
            inputIndex: pendingState.velocityIndex,
            uniforms: uniforms
        )
        pendingState.velocityIndex = 1 - pendingState.velocityIndex

        try encodeDivergence(
            commandBuffer: commandBuffer,
            velocityIndex: pendingState.velocityIndex,
            uniforms: uniforms
        )

        try encodeScalarClear(
            commandBuffer: commandBuffer,
            scalar: pressureTextures[0],
            uniforms: uniforms
        )
        try encodeScalarClear(
            commandBuffer: commandBuffer,
            scalar: pressureTextures[1],
            uniforms: uniforms
        )
        pendingState.pressureIndex = 0

        let iterationCount = min(Int(uniforms.particleCounts.w), 128)
        for _ in 0..<iterationCount {
            try encodeJacobi(
                commandBuffer: commandBuffer,
                pressureIndex: pendingState.pressureIndex,
                uniforms: uniforms
            )
            pendingState.pressureIndex = 1 - pendingState.pressureIndex
        }

        try encodePressureProjection(
            commandBuffer: commandBuffer,
            velocityIndex: pendingState.velocityIndex,
            pressureIndex: pendingState.pressureIndex,
            uniforms: uniforms
        )
        pendingState.velocityIndex = 1 - pendingState.velocityIndex
        stepState = pendingState
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
        let newVelocityTextures = try [
            makeTexture(pixelFormat: .rgba16Float, axis: axis, label: "Fluid Velocity A"),
            makeTexture(pixelFormat: .rgba16Float, axis: axis, label: "Fluid Velocity B"),
        ]
        let newPressureTextures = try [
            makeTexture(pixelFormat: .r16Float, axis: axis, label: "Fluid Pressure A"),
            makeTexture(pixelFormat: .r16Float, axis: axis, label: "Fluid Pressure B"),
        ]
        let newDivergenceTexture = try makeTexture(
            pixelFormat: .r16Float,
            axis: axis,
            label: "Fluid Divergence"
        )

        velocityTextures = newVelocityTextures
        pressureTextures = newPressureTextures
        divergenceTexture = newDivergenceTexture
        gridAxis = axis
        stepState = FluidStepState()
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
        guard let texture = textureFactory(descriptor) else {
            throw RendererError.pipeline("\(label) allocation")
        }
        texture.label = label
        return texture
    }

    private func encodeVelocityPass(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLComputePipelineState,
        label: String,
        inputIndex: Int,
        uniforms: GPUUniforms,
        force: InteractionForce? = nil
    ) throws {
        let encoder = try makeEncoder(commandBuffer: commandBuffer, label: label)
        encoder.label = label
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(velocityTextures[inputIndex], index: 0)
        encoder.setTexture(velocityTextures[1 - inputIndex], index: 1)
        set(uniforms, on: encoder, index: 0)
        if var force {
            encoder.setBytes(&force, length: MemoryLayout<InteractionForce>.stride, index: 1)
        }
        dispatch(encoder: encoder, pipeline: pipeline)
        encoder.endEncoding()
    }

    private func encodeDivergence(
        commandBuffer: MTLCommandBuffer,
        velocityIndex: Int,
        uniforms: GPUUniforms
    ) throws {
        let label = "Compute Fluid Divergence"
        let encoder = try makeEncoder(commandBuffer: commandBuffer, label: label)
        encoder.label = label
        encoder.setComputePipelineState(computeDivergencePipeline)
        encoder.setTexture(velocityTextures[velocityIndex], index: 0)
        encoder.setTexture(divergenceTexture, index: 1)
        set(uniforms, on: encoder, index: 0)
        dispatch(encoder: encoder, pipeline: computeDivergencePipeline)
        encoder.endEncoding()
    }

    private func encodeJacobi(
        commandBuffer: MTLCommandBuffer,
        pressureIndex: Int,
        uniforms: GPUUniforms
    ) throws {
        let label = "Solve Fluid Pressure"
        let encoder = try makeEncoder(commandBuffer: commandBuffer, label: label)
        encoder.label = label
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
        velocityIndex: Int,
        pressureIndex: Int,
        uniforms: GPUUniforms
    ) throws {
        let label = "Project Fluid Velocity"
        let encoder = try makeEncoder(commandBuffer: commandBuffer, label: label)
        encoder.label = label
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
    ) throws {
        let label = "Clear Fluid Resources"
        let encoder = try makeEncoder(commandBuffer: commandBuffer, label: label)
        encoder.label = label
        encoder.setComputePipelineState(clearFluidPipeline)
        encoder.setTexture(velocity, index: 0)
        encoder.setTexture(scalar, index: 1)
        set(uniforms, on: encoder, index: 0)
        dispatch(encoder: encoder, pipeline: clearFluidPipeline)
        encoder.endEncoding()
    }

    private func encodeScalarClear(
        commandBuffer: MTLCommandBuffer,
        scalar: MTLTexture,
        uniforms: GPUUniforms
    ) throws {
        let label = "Reset Fluid Pressure"
        let encoder = try makeEncoder(commandBuffer: commandBuffer, label: label)
        encoder.label = label
        encoder.setComputePipelineState(clearScalarPipeline)
        encoder.setTexture(scalar, index: 0)
        set(uniforms, on: encoder, index: 0)
        dispatch(encoder: encoder, pipeline: clearScalarPipeline)
        encoder.endEncoding()
    }

    private func makeEncoder(
        commandBuffer: MTLCommandBuffer,
        label: String
    ) throws -> MTLComputeCommandEncoder {
        guard let encoder = encoderFactory(commandBuffer) else {
            throw RendererError.commandEncoding(label)
        }
        return encoder
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
}
