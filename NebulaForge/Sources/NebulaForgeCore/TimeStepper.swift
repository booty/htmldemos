import Foundation

public struct StepSchedule: Equatable, Sendable {
    public let stepCount: Int
    public let stepDelta: Float

    public init(stepCount: Int, stepDelta: Float) {
        self.stepCount = stepCount
        self.stepDelta = stepDelta
    }
}

public struct TimeStepper: Sendable {
    public init() {}

    public func schedule(wallDelta: TimeInterval, speed: Float) -> StepSchedule {
        let safeWallDelta = min(max(wallDelta.isFinite ? wallDelta : 0, 0), 1.0 / 15.0)
        let total = safeWallDelta * Double(min(max(speed.isFinite ? speed : 1, 0), 2.5))
        guard total > 0 else { return StepSchedule(stepCount: 0, stepDelta: 0) }
        let count = min(4, max(1, Int(ceil(total / (1.0 / 60.0)))))
        return StepSchedule(stepCount: count, stepDelta: Float(total / Double(count)))
    }
}
