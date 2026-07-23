import XCTest
import NebulaForgeCore
@testable import NebulaForgeApp

final class NebulaForgeAppTests: XCTestCase {
    @MainActor
    func testAppModelStartsWithDefaultSimulationState() {
        let model = AppModel()

        XCTAssertEqual(model.parameters, .default)
        XCTAssertEqual(
            model.timeStepper.schedule(wallDelta: 1.0 / 60.0, speed: 1),
            StepSchedule(stepCount: 1, stepDelta: 1.0 / 60.0)
        )
        XCTAssertNil(model.rendererError)
    }

    func testRendererErrorsDescribeTheirFailingStage() {
        XCTAssertEqual(
            RendererError.noMetalDevice.errorDescription,
            "This Mac does not expose a Metal device."
        )
        XCTAssertEqual(
            RendererError.missingShaderResource("Shared").errorDescription,
            "Missing Metal shader resource: Shared.metal"
        )
        XCTAssertEqual(
            RendererError.shaderCompilation("bad source").errorDescription,
            "Metal shader compilation failed: bad source"
        )
        XCTAssertEqual(
            RendererError.pipeline("diagnostic render pipeline").errorDescription,
            "Metal pipeline creation failed for diagnostic render pipeline."
        )
        XCTAssertEqual(
            RendererError.commandEncoding("fluid projection").errorDescription,
            "Metal command encoding failed for fluid projection."
        )
    }

    func testRendererCommandsPreserveTheirPayloads() {
        let parameters = SimulationParameters.default

        XCTAssertEqual(RendererCommand.apply(parameters), .apply(parameters))
        XCTAssertEqual(RendererCommand.reset(parameters), .reset(parameters))
        XCTAssertEqual(RendererCommand.setPaused(true), .setPaused(true))
        XCTAssertEqual(RendererCommand.singleStep, .singleStep)
    }
}
