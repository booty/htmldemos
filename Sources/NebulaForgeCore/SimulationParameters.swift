import Foundation

public enum FluidGridAxis: Int, CaseIterable, Sendable { case n48 = 48, n64 = 64, n80 = 80, n96 = 96, n128 = 128, n160 = 160 }
public enum FrameRateTarget: Int, CaseIterable, Sendable { case fps30 = 30, fps60 = 60, fps120 = 120 }
public enum Palette: UInt32, CaseIterable, Sendable { case solar, aurora, supernova, void }

public struct SimulationParameters: Equatable, Sendable {
    public var activeParticles = 500_000
    public var emissionRate: Float = 100_000
    public var particleLifetime: Float = 7
    public var particleSize: Float = 1.8
    public var particleDrag: Float = 1.5
    public var fluidGridAxis = FluidGridAxis.n96
    public var simulationSpeed: Float = 1
    public var viscosity: Float = 0.001
    public var velocityDissipation: Float = 0.15
    public var pressureIterations = 32
    public var vorticityStrength: Float = 4
    public var gravityMagnitude: Float = 0
    public var attractionMagnitude: Float = 16
    public var orbitalForceMagnitude: Float = 20
    public var turbulenceScale: Float = 2
    public var turbulenceStrength: Float = 8
    public var emitterPosition = SIMD3<Float>(0, 0, 0)
    public var emitterRadius: Float = 0.12
    public var emitterDirection = SIMD3<Float>(0, 1, 0)
    public var emitterSpread: Float = 0.35
    public var emitterInitialVelocity: Float = 0.4
    public var palette = Palette.solar
    public var velocityColorMix: Float = 0.75
    public var exposure: Float = 0
    public var bloomIntensity: Float = 1.1
    public var bloomRadius: Float = 8
    public var trailPersistence: Float = 0.86
    public var depthFog: Float = 0.2
    public var backgroundIntensity: Float = 0.02
    public var cameraOrbitSpeed: Float = 0.12
    public var fieldOfViewDegrees: Float = 52
    public var automaticCinematicCamera = false
    public var renderScale: Float = 1
    public var targetFrameRate = FrameRateTarget.fps60
    public var adaptiveQuality = true

    public static let `default` = SimulationParameters()

    public func validated() -> Self {
        var result = self
        func finite(_ value: Float, fallback: Float, _ range: ClosedRange<Float>) -> Float {
            value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        result.activeParticles = min(max(activeParticles, 50_000), 2_000_000)
        result.emissionRate = finite(emissionRate, fallback: 100_000, 1_000...500_000)
        result.particleLifetime = finite(particleLifetime, fallback: 7, 0.5...20)
        result.particleSize = finite(particleSize, fallback: 1.8, 0.25...8)
        result.particleDrag = finite(particleDrag, fallback: 1.5, 0...8)
        result.simulationSpeed = finite(simulationSpeed, fallback: 1, 0...2.5)
        result.viscosity = finite(viscosity, fallback: 0.001, 0...0.02)
        result.velocityDissipation = finite(velocityDissipation, fallback: 0.15, 0...4)
        result.pressureIterations = min(max(pressureIterations, 8), 80)
        result.vorticityStrength = finite(vorticityStrength, fallback: 4, 0...12)
        result.gravityMagnitude = finite(gravityMagnitude, fallback: 0, 0...20)
        result.attractionMagnitude = finite(attractionMagnitude, fallback: 16, 0...60)
        result.orbitalForceMagnitude = finite(orbitalForceMagnitude, fallback: 20, 0...60)
        result.turbulenceScale = finite(turbulenceScale, fallback: 2, 0.2...8)
        result.turbulenceStrength = finite(turbulenceStrength, fallback: 8, 0...40)
        result.emitterPosition = SIMD3(
            finite(emitterPosition.x, fallback: 0, -1...1),
            finite(emitterPosition.y, fallback: 0, -1...1),
            finite(emitterPosition.z, fallback: 0, -1...1)
        )
        result.emitterRadius = finite(emitterRadius, fallback: 0.12, 0.01...0.75)
        let directionLength = emitterDirection.length
        result.emitterDirection = directionLength.isFinite && directionLength > 0.0001 ? emitterDirection / directionLength : SIMD3(0, 1, 0)
        result.emitterSpread = finite(emitterSpread, fallback: 0.35, 0...1)
        result.emitterInitialVelocity = finite(emitterInitialVelocity, fallback: 0.4, 0...20)
        result.velocityColorMix = finite(velocityColorMix, fallback: 0.75, 0...1)
        result.exposure = finite(exposure, fallback: 0, -4...4)
        result.bloomIntensity = finite(bloomIntensity, fallback: 1.1, 0...3)
        result.bloomRadius = finite(bloomRadius, fallback: 8, 0...24)
        result.trailPersistence = finite(trailPersistence, fallback: 0.86, 0...0.98)
        result.depthFog = finite(depthFog, fallback: 0.2, 0...1)
        result.backgroundIntensity = finite(backgroundIntensity, fallback: 0.02, 0...0.4)
        result.cameraOrbitSpeed = finite(cameraOrbitSpeed, fallback: 0.12, 0...1)
        result.fieldOfViewDegrees = finite(fieldOfViewDegrees, fallback: 52, 25...90)
        result.renderScale = finite(renderScale, fallback: 1, 0.5...1)
        return result
    }
}

private extension SIMD3 where Scalar == Float {
    var length: Float { sqrt(x * x + y * y + z * z) }
}
