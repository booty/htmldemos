import XCTest
import NebulaForgeCore
@testable import NebulaForgeApp

final class GPUSharedLayoutTests: XCTestCase {
    func testGPUUniformLayoutIsSixteenByteAligned() {
        XCTAssertEqual(MemoryLayout<GPUUniforms>.stride % 16, 0)
        XCTAssertEqual(MemoryLayout<InteractionForce>.stride % 16, 0)
    }

    func testGPUUniformLayoutMatchesMetalABI() {
        XCTAssertEqual(MemoryLayout<GPUUniforms>.stride, 112)
        XCTAssertEqual(MemoryLayout<InteractionForce>.stride, 48)
    }

    func testGPUUniformsPackValidatedSimulationInputs() {
        var parameters = SimulationParameters.default
        parameters.fluidGridAxis = .n64
        parameters.velocityDissipation = 0.25
        parameters.viscosity = 0.005
        parameters.gravityMagnitude = 2
        parameters.attractionMagnitude = 3
        parameters.orbitalForceMagnitude = 4
        parameters.vorticityStrength = 5

        let uniforms = GPUUniforms(
            parameters: parameters,
            schedule: StepSchedule(stepCount: 2, stepDelta: 0.01),
            elapsedTime: 1.5,
            frameIndex: 7,
            particleCapacity: 2_000_000
        )

        XCTAssertEqual(uniforms.gridSize, SIMD4(64, 64, 64, 0))
        XCTAssertEqual(uniforms.deltaAndTime, SIMD4(0.01, 1.5, 0.25, 0.005))
        XCTAssertEqual(uniforms.forces, SIMD4(2, 3, 4, 5))
        XCTAssertEqual(uniforms.particleCounts, SIMD4(500_000, 2_000_000, 7, 32))
    }
}
