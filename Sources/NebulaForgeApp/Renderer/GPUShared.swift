import NebulaForgeCore

struct GPUUniforms {
    var gridSize: SIMD4<UInt32>
    var deltaAndTime: SIMD4<Float>
    var forces: SIMD4<Float>
    var turbulence: SIMD4<Float>
    var emitterPositionRadius: SIMD4<Float>
    var emitterDirectionSpeed: SIMD4<Float>
    var particleCounts: SIMD4<UInt32>

    init(
        parameters: SimulationParameters,
        schedule: StepSchedule,
        elapsedTime: Float,
        frameIndex: UInt32,
        particleCapacity: Int
    ) {
        let parameters = parameters.validated()
        let axis = UInt32(parameters.fluidGridAxis.rawValue)
        gridSize = SIMD4(axis, axis, axis, 0)
        deltaAndTime = SIMD4(
            schedule.stepDelta,
            elapsedTime,
            parameters.velocityDissipation,
            parameters.viscosity
        )
        forces = SIMD4(
            parameters.gravityMagnitude,
            parameters.attractionMagnitude,
            parameters.orbitalForceMagnitude,
            parameters.vorticityStrength
        )
        turbulence = SIMD4(
            parameters.turbulenceScale,
            parameters.turbulenceStrength,
            parameters.emissionRate,
            parameters.particleDrag
        )
        emitterPositionRadius = SIMD4(
            parameters.emitterPosition.x,
            parameters.emitterPosition.y,
            parameters.emitterPosition.z,
            parameters.emitterRadius
        )
        emitterDirectionSpeed = SIMD4(
            parameters.emitterDirection.x,
            parameters.emitterDirection.y,
            parameters.emitterDirection.z,
            parameters.emitterInitialVelocity
        )
        particleCounts = SIMD4(
            UInt32(parameters.activeParticles),
            UInt32(max(0, particleCapacity)),
            frameIndex,
            UInt32(parameters.pressureIterations)
        )
    }
}

struct InteractionForce {
    var positionRadius: SIMD4<Float>
    var directionStrength: SIMD4<Float>
    var modeAndPadding: SIMD4<UInt32>

    static let inactive = InteractionForce(
        positionRadius: .zero,
        directionStrength: .zero,
        modeAndPadding: .zero
    )
}

struct GPUParticle {
    var positionAge: SIMD4<Float>
    var previousPositionLifetime: SIMD4<Float>
    var velocitySeed: SIMD4<Float>

    var position: SIMD3<Float> {
        SIMD3(positionAge.x, positionAge.y, positionAge.z)
    }

    var age: Float { positionAge.w }

    var lifetime: Float { previousPositionLifetime.w }
}
