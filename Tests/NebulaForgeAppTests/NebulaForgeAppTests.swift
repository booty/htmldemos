import XCTest
import NebulaForgeCore
@testable import NebulaForgeApp

final class NebulaForgeAppTests: XCTestCase {
    @MainActor
    func testAppModelStartsWithDefaultSimulationState() {
        let model = AppModel()

        XCTAssertEqual(model.parameters, Preset.solarMaelstrom.parameters)
        XCTAssertEqual(model.selectedPreset, .preset(.solarMaelstrom))
        XCTAssertFalse(model.isPaused)
        XCTAssertTrue(model.panelVisible)
        XCTAssertFalse(model.performanceVisible)
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

    @MainActor
    func testApplyParametersValidatesModelAndForwardsSnapshot() {
        let renderer = RendererCommandSpy()
        let model = AppModel()
        model.renderer = renderer
        model.parameters.emissionRate = .infinity
        model.parameters.activeParticles = 4_000_000

        model.applyParameters()

        XCTAssertEqual(model.parameters.emissionRate, 100_000)
        XCTAssertEqual(model.parameters.activeParticles, 2_000_000)
        XCTAssertEqual(renderer.commands, [.apply(model.parameters)])
    }

    @MainActor
    func testPresetSelectionUpdatesEveryControlAndResetsRenderer() {
        let renderer = RendererCommandSpy()
        let model = AppModel()
        model.renderer = renderer

        model.applyPreset(.blackHole)

        XCTAssertEqual(model.selectedPreset, .preset(.blackHole))
        XCTAssertEqual(model.parameters, Preset.blackHole.parameters)
        XCTAssertEqual(renderer.commands, [.reset(Preset.blackHole.parameters)])
    }

    @MainActor
    func testPauseSingleStepAndResumeRouteCommandsInOrder() {
        let renderer = RendererCommandSpy()
        let model = AppModel()
        model.renderer = renderer

        model.togglePause()
        model.singleStep()
        model.togglePause()

        XCTAssertFalse(model.isPaused)
        XCTAssertEqual(renderer.commands, [
            .setPaused(true),
            .singleStep,
            .setPaused(false),
        ])
    }

    @MainActor
    func testResetValidatesControlsAndResetsRenderer() {
        let renderer = RendererCommandSpy()
        let model = AppModel()
        model.renderer = renderer
        model.parameters.exposure = 50

        model.reset()

        XCTAssertEqual(model.parameters.exposure, 4)
        XCTAssertEqual(renderer.commands, [.reset(model.parameters)])
    }

    @MainActor
    func testSeededRandomizeIsDeterministicAndWithinValidatedRanges() {
        let firstRenderer = RendererCommandSpy()
        let secondRenderer = RendererCommandSpy()
        let first = AppModel()
        let second = AppModel()
        first.renderer = firstRenderer
        second.renderer = secondRenderer

        first.randomize(seed: 0x1234)
        second.randomize(seed: 0x1234)

        XCTAssertEqual(first.parameters, second.parameters)
        XCTAssertEqual(first.parameters, first.parameters.validated())
        XCTAssertEqual(firstRenderer.commands, [.apply(first.parameters)])
        XCTAssertEqual(secondRenderer.commands, [.apply(second.parameters)])
    }

    func testRendererStateValidatesAndCoalescesLiveApply() {
        var state = RendererCommandState(parameters: .default)
        var first = SimulationParameters.default
        first.exposure = 99
        var second = SimulationParameters.default
        second.emissionRate = 2_000

        state.apply(.apply(first))
        state.apply(.apply(second))
        let update = state.consume()

        XCTAssertEqual(update.parameters, second.validated())
        XCTAssertFalse(update.isPaused)
        XCTAssertEqual(update.singleStepCount, 0)
        XCTAssertFalse(update.resetsSimulation)
        XCTAssertFalse(update.resetsTemporalHistory)
    }

    func testRendererStateOnlyQueuesFixedStepsWhilePaused() {
        var state = RendererCommandState(parameters: .default)

        state.apply(.singleStep)
        state.apply(.setPaused(true))
        state.apply(.singleStep)
        state.apply(.singleStep)
        let update = state.consume()

        XCTAssertTrue(update.isPaused)
        XCTAssertEqual(update.singleStepCount, 2)
        XCTAssertEqual(update.singleStepDelta, 1.0 / 60.0)
        XCTAssertEqual(state.consume().singleStepCount, 0)
    }

    func testRendererStateResumeDiscardsUnconsumedSingleSteps() {
        var state = RendererCommandState(parameters: .default)
        state.apply(.setPaused(true))
        state.apply(.singleStep)
        state.apply(.setPaused(false))

        let update = state.consume()

        XCTAssertFalse(update.isPaused)
        XCTAssertEqual(update.singleStepCount, 0)
    }

    func testRendererStateResetCausesCancelOnlyPreviouslyQueuedSingleSteps() {
        var resetState = RendererCommandState(parameters: .default)
        resetState.apply(.setPaused(true))
        resetState.apply(.singleStep)
        resetState.apply(.reset(.default))
        resetState.apply(.singleStep)

        var gridState = RendererCommandState(parameters: .default)
        var gridChange = SimulationParameters.default
        gridChange.fluidGridAxis = .n128
        gridState.apply(.setPaused(true))
        gridState.apply(.singleStep)
        gridState.apply(.apply(gridChange))
        gridState.apply(.singleStep)

        XCTAssertEqual(resetState.consume().singleStepCount, 1)
        XCTAssertEqual(gridState.consume().singleStepCount, 1)
    }

    func testRendererStateRetainsResetUntilItIsCompleted() {
        var state = RendererCommandState(parameters: .default)
        state.apply(.reset(.default))

        let staleAttempt = state.consume()
        state.apply(.reset(.default))
        state.acknowledgeResets(from: staleAttempt)
        let currentAttempt = state.consume()

        XCTAssertTrue(currentAttempt.resetsSimulation)
        XCTAssertTrue(currentAttempt.resetsTemporalHistory)

        state.acknowledgeResets(from: currentAttempt)
        let completedUpdate = state.consume()
        XCTAssertFalse(completedUpdate.resetsSimulation)
        XCTAssertFalse(completedUpdate.resetsTemporalHistory)
    }

    func testSimulationResetCompletionPreservesOnlyNewerTemporalReset() {
        var state = RendererCommandState(parameters: .default)
        state.apply(.reset(.default))
        let simulationReset = state.consume()

        var renderScaleChange = SimulationParameters.default
        renderScaleChange.renderScale = 0.75
        state.apply(.apply(renderScaleChange))
        state.acknowledgeResets(from: simulationReset)

        let remainingUpdate = state.consume()
        XCTAssertFalse(remainingUpdate.resetsSimulation)
        XCTAssertTrue(remainingUpdate.resetsTemporalHistory)
    }

    func testRendererStateResetAndGridChangeRequestFullStateReset() {
        var state = RendererCommandState(parameters: .default)
        var gridChange = SimulationParameters.default
        gridChange.fluidGridAxis = .n128

        state.apply(.apply(gridChange))
        var update = state.consume()
        XCTAssertTrue(update.resetsSimulation)
        XCTAssertTrue(update.resetsTemporalHistory)

        state.apply(.reset(.default))
        update = state.consume()
        XCTAssertTrue(update.resetsSimulation)
        XCTAssertTrue(update.resetsTemporalHistory)
        state.acknowledgeResets(from: update)
        XCTAssertFalse(state.consume().resetsSimulation)
    }

    func testRendererStateRenderScaleChangeOnlyResetsTemporalHistory() {
        var state = RendererCommandState(parameters: .default)
        var renderScaleChange = SimulationParameters.default
        renderScaleChange.renderScale = 0.75

        state.apply(.apply(renderScaleChange))
        let update = state.consume()

        XCTAssertFalse(update.resetsSimulation)
        XCTAssertTrue(update.resetsTemporalHistory)
    }

    @MainActor
    func testLiveEditsAndRandomizeSelectCustomUntilPresetIsApplied() {
        let model = AppModel()
        model.parameters.exposure = 1

        model.applyParameters()
        XCTAssertEqual(model.selectedPreset, .custom)

        model.applyPreset(.aurora)
        XCTAssertEqual(model.selectedPreset, .preset(.aurora))

        model.randomize(seed: 0x1234)
        XCTAssertEqual(model.selectedPreset, .custom)
    }

    func testLogarithmicScaleRoundTripsPositiveAndZeroBasedRanges() {
        let positive = LogarithmicScale(range: 1_000...500_000)
        let zeroBased = LogarithmicScale(range: 0...0.02)

        XCTAssertEqual(positive.value(at: positive.position(of: 100_000)), 100_000, accuracy: 0.01)
        XCTAssertEqual(zeroBased.value(at: zeroBased.position(of: 0)), 0)
        XCTAssertEqual(zeroBased.value(at: zeroBased.position(of: 0.001)), 0.001, accuracy: 0.000_001)
        XCTAssertEqual(zeroBased.value(at: 1), 0.02, accuracy: 0.000_001)
    }
}

@MainActor
private final class RendererCommandSpy: RendererCommandTarget {
    private(set) var commands: [RendererCommand] = []

    func apply(_ parameters: SimulationParameters) {
        commands.append(.apply(parameters))
    }

    func reset(_ parameters: SimulationParameters) {
        commands.append(.reset(parameters))
    }

    func setPaused(_ paused: Bool) {
        commands.append(.setPaused(paused))
    }

    func singleStep() {
        commands.append(.singleStep)
    }
}
