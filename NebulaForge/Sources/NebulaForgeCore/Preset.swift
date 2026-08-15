public enum Preset: String, CaseIterable, Identifiable, Sendable {
    case solarMaelstrom = "Solar Maelstrom"
    case aurora = "Aurora"
    case supernova = "Supernova"
    case blackHole = "Black Hole"

    public var id: String { rawValue }

    public var parameters: SimulationParameters {
        var p = SimulationParameters.default
        switch self {
        case .solarMaelstrom:
            break
        case .aurora:
            p.activeParticles = 700_000
            p.vorticityStrength = 7
            p.gravityMagnitude = 2
            p.attractionMagnitude = 6
            p.orbitalForceMagnitude = 10
            p.trailPersistence = 0.91
            p.palette = .aurora
        case .supernova:
            p.activeParticles = 900_000
            p.emissionRate = 350_000
            p.particleLifetime = 3.5
            p.attractionMagnitude = 2
            p.orbitalForceMagnitude = 3
            p.turbulenceStrength = 22
            p.exposure = 0.8
            p.bloomIntensity = 1.8
            p.palette = .supernova
        case .blackHole:
            p.activeParticles = 800_000
            p.particleLifetime = 10
            p.attractionMagnitude = 42
            p.orbitalForceMagnitude = 48
            p.vorticityStrength = 8
            p.trailPersistence = 0.93
            p.palette = .void
        }
        return p.validated()
    }

    public static func randomized(seed: UInt64) -> SimulationParameters {
        var rng = SplitMix64(state: seed)
        func sample(_ range: ClosedRange<Float>) -> Float {
            range.lowerBound + Float(rng.next() & 0x00ff_ffff) / Float(0x00ff_ffff) * (range.upperBound - range.lowerBound)
        }
        var p = SimulationParameters.default
        p.vorticityStrength = sample(1...12)
        p.attractionMagnitude = sample(0...60)
        p.orbitalForceMagnitude = sample(0...60)
        p.turbulenceScale = sample(0.2...8)
        p.turbulenceStrength = sample(0...40)
        p.exposure = sample(-1.5...1.5)
        p.bloomIntensity = sample(0.4...2.5)
        p.trailPersistence = sample(0.4...0.96)
        return p.validated()
    }
}

private struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
