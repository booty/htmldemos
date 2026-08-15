import NebulaForgeCore
import Observation

@MainActor
protocol RendererCommandTarget: AnyObject {
    func apply(_ parameters: SimulationParameters)
    func reset(_ parameters: SimulationParameters)
    func setPaused(_ paused: Bool)
    func singleStep()
}

enum RendererCommand: Equatable, Sendable {
    case apply(SimulationParameters)
    case reset(SimulationParameters)
    case setPaused(Bool)
    case singleStep
}

enum PresetSelection: Equatable, Hashable, Sendable {
    case preset(Preset)
    case custom
}

@MainActor
@Observable
final class AppModel {
    var parameters = Preset.solarMaelstrom.parameters
    var selectedPreset = PresetSelection.preset(.solarMaelstrom)
    var isPaused = false
    var panelVisible = true
    var performanceVisible = false
    let timeStepper = TimeStepper()
    var rendererError: RendererError?
    weak var renderer: (any RendererCommandTarget)?

    func applyParameters() {
        parameters = parameters.validated()
        selectedPreset = .custom
        renderer?.apply(parameters)
    }

    func applyPreset(_ preset: Preset) {
        selectedPreset = .preset(preset)
        parameters = preset.parameters
        renderer?.reset(parameters)
    }

    func togglePause() {
        isPaused.toggle()
        renderer?.setPaused(isPaused)
    }

    func singleStep() {
        renderer?.singleStep()
    }

    func reset() {
        parameters = parameters.validated()
        renderer?.reset(parameters)
    }

    func randomize() {
        randomize(seed: UInt64.random(in: .min ... .max))
    }

    func randomize(seed: UInt64) {
        parameters = Preset.randomized(seed: seed)
        applyParameters()
    }
}
