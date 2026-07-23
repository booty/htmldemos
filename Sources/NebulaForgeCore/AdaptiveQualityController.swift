public struct QualityState: Equatable, Sendable {
    public var renderScale: Float {
        didSet { renderScale = Self.clampedRenderScale(renderScale) }
    }
    public var activeParticles: Int {
        didSet { activeParticles = min(max(activeParticles, 50_000), 2_000_000) }
    }
    public var fluidGridAxis: FluidGridAxis

    public init(renderScale: Float, activeParticles: Int, fluidGridAxis: FluidGridAxis) {
        self.renderScale = Self.clampedRenderScale(renderScale)
        self.activeParticles = min(max(activeParticles, 50_000), 2_000_000)
        self.fluidGridAxis = fluidGridAxis
    }

    private static func clampedRenderScale(_ value: Float) -> Float {
        value.isFinite ? min(max(value, 0.5), 1) : 1
    }

    fileprivate func clamped() -> Self {
        Self(renderScale: renderScale, activeParticles: activeParticles, fluidGridAxis: fluidGridAxis)
    }
}

public struct AdaptiveQualityController: Sendable {
    private var smoothed = 1.0 / 60.0
    private var pressureFrames = 0
    private var recoveryFrames = 0
    private var current: QualityState?

    public init() {}

    public mutating func update(frameTime: Double, targetFPS: Int, desired: QualityState) -> QualityState {
        let boundedDesired = desired.clamped()
        var quality = (current ?? boundedDesired).clamped()
        quality.renderScale = min(quality.renderScale, boundedDesired.renderScale)
        quality.activeParticles = min(quality.activeParticles, boundedDesired.activeParticles)
        if quality.fluidGridAxis.rawValue > boundedDesired.fluidGridAxis.rawValue {
            quality.fluidGridAxis = boundedDesired.fluidGridAxis
        }
        smoothed = smoothed * 0.9 + min(max(frameTime, 0), 0.25) * 0.1
        let validatedTargetFPS = FrameRateTarget(rawValue: targetFPS)?.rawValue ?? FrameRateTarget.fps60.rawValue
        let budget = 1.0 / Double(validatedTargetFPS)
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
            if quality.fluidGridAxis.rawValue < boundedDesired.fluidGridAxis.rawValue {
                quality.fluidGridAxis = FluidGridAxis.allCases.first(where: { $0.rawValue > quality.fluidGridAxis.rawValue && $0.rawValue <= boundedDesired.fluidGridAxis.rawValue }) ?? boundedDesired.fluidGridAxis
            } else if quality.activeParticles < boundedDesired.activeParticles {
                quality.activeParticles = min(boundedDesired.activeParticles, Int(Double(quality.activeParticles) * 1.1))
            } else {
                quality.renderScale = min(boundedDesired.renderScale, quality.renderScale + 0.05)
            }
            recoveryFrames = 0
        }
        current = quality.clamped()
        return current!
    }
}
