import NebulaForgeCore
import Observation

enum RendererCommand: Equatable, Sendable {
    case apply(SimulationParameters)
    case reset(SimulationParameters)
    case setPaused(Bool)
    case singleStep
}

@MainActor
@Observable
final class AppModel {
    var parameters = SimulationParameters.default
    let timeStepper = TimeStepper()
    var rendererError: RendererError?
    weak var renderer: MetalRenderer?
}
