public struct QualityState: Equatable, Sendable {
    public var renderScale: Float
    public var activeParticles: Int
    public var fluidGridAxis: FluidGridAxis

    public init(renderScale: Float, activeParticles: Int, fluidGridAxis: FluidGridAxis) {
        self.renderScale = renderScale
        self.activeParticles = activeParticles
        self.fluidGridAxis = fluidGridAxis
    }
}

public struct AdaptiveQualityController: Sendable {
    private var smoothed = 1.0 / 60.0
    private var pressureFrames = 0
    private var recoveryFrames = 0
    private var current: QualityState?

    public init() {}

    public mutating func update(frameTime: Double, targetFPS: Int, desired: QualityState) -> QualityState {
        var quality = current ?? desired
        smoothed = smoothed * 0.9 + min(max(frameTime, 0), 0.25) * 0.1
        let budget = 1.0 / Double(targetFPS)
        pressureFrames = smoothed > budget * 1.12 ? pressureFrames + 1 : 0
        recoveryFrames = smoothed < budget * 0.82 ? recoveryFrames + 1 : 0
        if pressureFrames >= 30 {
            if quality.renderScale > 0.5 {
                quality.renderScale = max(0.5, quality.renderScale - 0.1)
            } else if quality.activeParticles > 50_000 {
                quality.activeParticles = max(50_000, Int(Double(quality.activeParticles) * 0.85))
            } else {
                quality.fluidGridAxis = FluidGridAxis.allCases.last(where: { $0.rawValue < quality.fluidGridAxis.rawValue }) ?? .n48
            }
            pressureFrames = 0
        } else if recoveryFrames >= 180 {
            if quality.fluidGridAxis.rawValue < desired.fluidGridAxis.rawValue {
                quality.fluidGridAxis = FluidGridAxis.allCases.first(where: { $0.rawValue > quality.fluidGridAxis.rawValue && $0.rawValue <= desired.fluidGridAxis.rawValue }) ?? desired.fluidGridAxis
            } else if quality.activeParticles < desired.activeParticles {
                quality.activeParticles = min(desired.activeParticles, Int(Double(quality.activeParticles) * 1.1))
            } else {
                quality.renderScale = min(desired.renderScale, quality.renderScale + 0.05)
            }
            recoveryFrames = 0
        }
        current = quality
        return quality
    }
}
