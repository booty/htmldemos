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

    func testQualityStateClampsNumericValuesToDocumentedRanges() {
        let state = QualityState(renderScale: .infinity, activeParticles: 3_000_000, fluidGridAxis: .n96)

        XCTAssertEqual(state.renderScale, 1)
        XCTAssertEqual(state.activeParticles, 2_000_000)
    }

    func testInvalidTargetFPSUsesSixtyFPSBudget() {
        var controller = AdaptiveQualityController()
        let desired = QualityState(renderScale: 1, activeParticles: 500_000, fluidGridAxis: .n96)
        var result = desired

        for _ in 0..<45 {
            result = controller.update(frameTime: 1.0 / 40.0, targetFPS: 0, desired: desired)
        }

        XCTAssertLessThan(result.renderScale, desired.renderScale)
    }

    func testLowerDesiredMaximaApplyImmediately() {
        var controller = AdaptiveQualityController()
        let initial = QualityState(renderScale: 1, activeParticles: 500_000, fluidGridAxis: .n96)
        _ = controller.update(frameTime: 1.0 / 60.0, targetFPS: 60, desired: initial)
        let lowered = QualityState(renderScale: 0.7, activeParticles: 200_000, fluidGridAxis: .n64)

        let result = controller.update(frameTime: 1.0 / 60.0, targetFPS: 60, desired: lowered)

        XCTAssertEqual(result.renderScale, 0.7)
        XCTAssertEqual(result.activeParticles, 200_000)
        XCTAssertEqual(result.fluidGridAxis, .n64)
    }

    func testAdaptiveQualityRestoresGridThenParticlesThenRenderScale() {
        var controller = AdaptiveQualityController()
        let lowest = QualityState(renderScale: 0.5, activeParticles: 50_000, fluidGridAxis: .n96)
        var result = lowest

        for _ in 0..<200 {
            result = controller.update(frameTime: 0.25, targetFPS: 60, desired: lowest)
        }
        XCTAssertEqual(result.fluidGridAxis, .n48)

        let desired = QualityState(renderScale: 1, activeParticles: 500_000, fluidGridAxis: .n96)
        var changes: [QualityState] = []
        var previous = result
        for _ in 0..<7_000 {
            result = controller.update(frameTime: 0, targetFPS: 60, desired: desired)
            if result != previous {
                changes.append(result)
                previous = result
            }
            if result.renderScale > 0.5 { break }
        }

        XCTAssertGreaterThanOrEqual(changes.count, 5)
        XCTAssertEqual(changes[0], QualityState(renderScale: 0.5, activeParticles: 50_000, fluidGridAxis: .n64))
        XCTAssertEqual(changes[1], QualityState(renderScale: 0.5, activeParticles: 50_000, fluidGridAxis: .n80))
        XCTAssertEqual(changes[2], QualityState(renderScale: 0.5, activeParticles: 50_000, fluidGridAxis: .n96))
        XCTAssertEqual(changes[3].fluidGridAxis, .n96)
        XCTAssertGreaterThan(changes[3].activeParticles, 50_000)
        XCTAssertEqual(changes[3].renderScale, 0.5)
        XCTAssertEqual(result.fluidGridAxis, .n96)
        XCTAssertEqual(result.activeParticles, desired.activeParticles)
        XCTAssertGreaterThan(result.renderScale, 0.5)
    }
}
