import XCTest
@testable import NebulaForgeCore

final class SimulationParametersTests: XCTestCase {
    func testValidationClampsEveryScalarBoundary() {
        var value = SimulationParameters.default
        value.activeParticles = 3_000_000
        value.particleLifetime = -1
        value.pressureIterations = 200
        value.renderScale = 0.1
        value.trailPersistence = 2

        let result = value.validated()

        XCTAssertEqual(result.activeParticles, 2_000_000)
        XCTAssertEqual(result.particleLifetime, 0.5)
        XCTAssertEqual(result.pressureIterations, 80)
        XCTAssertEqual(result.renderScale, 0.5)
        XCTAssertEqual(result.trailPersistence, 0.98)
    }

    func testValidationReplacesNonFiniteValues() {
        var value = SimulationParameters.default
        value.viscosity = .nan
        value.exposure = .infinity
        let result = value.validated()
        XCTAssertEqual(result.viscosity, SimulationParameters.default.viscosity)
        XCTAssertEqual(result.exposure, SimulationParameters.default.exposure)
    }
}
