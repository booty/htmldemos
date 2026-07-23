import XCTest
import Metal
import NebulaForgeCore
import simd
@testable import NebulaForgeApp

final class MetalKernelTests: XCTestCase {
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
    private var velocityIndex = 0
    private var pressureIndex = 0
    private var uniforms: GPUUniforms

    init(gridAxis: Int) throws {
        context = try MetalContext()
        self.gridAxis = gridAxis
        computeDivergencePipeline = try Self.pipeline(named: "computeDivergence", context: context)
        jacobiPressurePipeline = try Self.pipeline(named: "jacobiPressure", context: context)
        subtractPressureGradientPipeline = try Self.pipeline(
            named: "subtractPressureGradient",
            context: context
        )
        velocityTextures = try [
            Self.texture(context: context, format: .rgba16Float, axis: gridAxis),
            Self.texture(context: context, format: .rgba16Float, axis: gridAxis),
        ]
        pressureTextures = try [
            Self.texture(context: context, format: .r16Float, axis: gridAxis),
            Self.texture(context: context, format: .r16Float, axis: gridAxis),
        ]
        divergenceTexture = try Self.texture(
            context: context,
            format: .r16Float,
            axis: gridAxis
        )
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
        guard let commandBuffer = context.queue.makeCommandBuffer() else {
            throw MetalHarnessError.commandEncoding
        }
        try encodeDivergence(commandBuffer: commandBuffer)
        try commitAndWait(commandBuffer)

        var values = [Float16](repeating: 0, count: gridAxis * gridAxis * gridAxis)
        read(texture: divergenceTexture, into: &values, components: 1)
        return values.lazy.map { abs(Float($0)) }.max() ?? 0
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

    private func encodeDivergence(commandBuffer: MTLCommandBuffer) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalHarnessError.commandEncoding
        }
        encoder.setComputePipelineState(computeDivergencePipeline)
        encoder.setTexture(velocityTextures[velocityIndex], index: 0)
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

    private func setUniforms(on encoder: MTLComputeCommandEncoder) {
        var uniforms = uniforms
        encoder.setBytes(&uniforms, length: MemoryLayout<GPUUniforms>.stride, index: 0)
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

    private func commitAndWait(_ commandBuffer: MTLCommandBuffer) throws {
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw MetalHarnessError.commandFailure(commandBuffer.error)
        }
    }
}
