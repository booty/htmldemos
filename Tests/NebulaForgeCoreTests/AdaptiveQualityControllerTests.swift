import XCTest
@testable import NebulaForgeCore

final class AdaptiveQualityControllerTests: XCTestCase {
    func testAdaptiveQualityLowersRenderScaleBeforeParticles() {
        var controller = AdaptiveQualityController()
        let desired = QualityState(renderScale: 1, activeParticles: 500_000, fluidGridAxis: .n96)
        var result = desired

        for _ in 0..<45 {
            result = controller.update(frameTime: 1.0 / 40.0, targetFPS: 60, desired: desired)
        }

        XCTAssertLessThan(result.renderScale, 1)
        XCTAssertEqual(result.activeParticles, 500_000)
        XCTAssertEqual(result.fluidGridAxis, .n96)
    }

    func testAdaptiveQualityLowersParticlesBeforeGridResolution() {
        var controller = AdaptiveQualityController()
        let desired = QualityState(renderScale: 0.5, activeParticles: 100_000, fluidGridAxis: .n96)
        var result = desired

        for _ in 0..<75 {
            result = controller.update(frameTime: 1.0 / 20.0, targetFPS: 60, desired: desired)
        }

        XCTAssertLessThan(result.activeParticles, desired.activeParticles)
        XCTAssertEqual(result.fluidGridAxis, desired.fluidGridAxis)
    }
}
