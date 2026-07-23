#include <metal_stdlib>
using namespace metal;

static uint particleHash(uint value) {
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    value ^= value >> 16;
    return value;
}

static float particleRandom(uint value) {
    return float(particleHash(value) & 0x00ffffffu) / float(0x01000000u);
}

static float3 deterministicUnitBall(uint seed) {
    float3 direction = float3(
        particleRandom(seed ^ 0x68bc21ebu) * 2.0f - 1.0f,
        particleRandom(seed ^ 0x02e5be93u) * 2.0f - 1.0f,
        particleRandom(seed ^ 0x967a889bu) * 2.0f - 1.0f
    );
    float directionLength = length(direction);
    if (!isfinite(directionLength) || directionLength < 1.0e-5f) {
        direction = float3(0.0f, 1.0f, 0.0f);
    } else {
        direction /= directionLength;
    }
    float radius = pow(particleRandom(seed ^ 0x368cc8b7u), 1.0f / 3.0f);
    return direction * radius;
}

static float3 deterministicLaunchDirection(
    uint seed,
    constant GPUUniforms& u
) {
    float3 axis = u.emitterDirectionSpeed.xyz;
    float axisLength = length(axis);
    axis = axisLength > 1.0e-5f
        ? axis / axisLength
        : float3(0.0f, 1.0f, 0.0f);
    float spread = clamp(u.particleBehavior.y, 0.0f, 1.0f);
    if (spread == 0.0f) return axis;

    float maximumAngle = spread * M_PI_2_F;
    float cosineTheta = mix(
        1.0f,
        cos(maximumAngle),
        particleRandom(seed ^ 0xc2b2ae35u)
    );
    float sineTheta = sqrt(max(1.0f - cosineTheta * cosineTheta, 0.0f));
    float phi = 2.0f * M_PI_F * particleRandom(seed ^ 0x27d4eb2fu);
    float3 reference = abs(axis.y) < 0.999f
        ? float3(0.0f, 1.0f, 0.0f)
        : float3(1.0f, 0.0f, 0.0f);
    float3 tangent = normalize(cross(reference, axis));
    float3 bitangent = cross(axis, tangent);
    return normalize(
        axis * cosineTheta
            + tangent * (cos(phi) * sineTheta)
            + bitangent * (sin(phi) * sineTheta)
    );
}

static GPUParticle respawnParticle(
    uint seed,
    constant GPUUniforms& u
) {
    uint respawnSeed = particleHash(seed ^ (u.particleCounts.z * 0x9e3779b9u));
    float3 offset = deterministicUnitBall(respawnSeed) * max(u.emitterPositionRadius.w, 0.0f);
    float3 position = clamp(u.emitterPositionRadius.xyz + offset, -1.0f, 1.0f);
    float3 direction = deterministicLaunchDirection(respawnSeed, u);
    float3 velocity = direction * max(u.emitterDirectionSpeed.w, 0.0f);
    float lifetime = max(u.particleBehavior.x, 0.5f);

    GPUParticle particle;
    particle.positionAge = float4(position, 0.0f);
    particle.previousPositionLifetime = float4(position, lifetime);
    particle.velocitySeed = float4(velocity, float(seed));
    return particle;
}

static GPUParticle dormantParticle(
    uint seed,
    float delay,
    constant GPUUniforms& u
) {
    float3 position = clamp(u.emitterPositionRadius.xyz, -1.0f, 1.0f);
    GPUParticle particle;
    // Negative age is the renderer-visible dormant invariant. Its magnitude
    // is the remaining delay in seconds before this particle can respawn.
    particle.positionAge = float4(position, -max(delay, 1.0e-6f));
    particle.previousPositionLifetime = float4(
        position,
        max(u.particleBehavior.x, 0.5f)
    );
    particle.velocitySeed = float4(0.0f, 0.0f, 0.0f, float(seed));
    return particle;
}

static GPUParticle recycleParticle(
    uint seed,
    uint particleIndex,
    float dt,
    uint activeCount,
    constant GPUUniforms& u
) {
    uint slot = particleIndex % max(activeCount, 1u);
    float recycleDelay = max(
        (float(slot) + particleRandom(seed ^ 0x85ebca6bu))
            / max(u.particleBehavior.z, 1.0f)
            - dt,
        0.0f
    );
    return recycleDelay > 0.0f
        ? dormantParticle(seed, recycleDelay, u)
        : respawnParticle(seed, u);
}

kernel void initializeParticles(
    device GPUParticle* particles [[buffer(0)]],
    constant uint4& initialization [[buffer(1)]],
    constant GPUUniforms& u [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    uint capacity = initialization.y;
    if (gid >= capacity) return;

    uint seed = (particleHash(gid ^ initialization.x) & 0x00ffffffu) | 1u;
    float3 position = clamp(
        u.emitterPositionRadius.xyz
            + deterministicUnitBall(seed) * max(u.emitterPositionRadius.w, 0.0f),
        -1.0f,
        1.0f
    );
    float lifetime = max(u.particleBehavior.x, 0.5f);
    float emissionRate = max(u.particleBehavior.z, 1.0f);
    float activationDelay = (
        float(gid) + particleRandom(seed ^ 0x1b56c4e9u)
    ) / emissionRate;

    GPUParticle particle;
    particle.positionAge = float4(position, -max(activationDelay, 1.0e-6f));
    particle.previousPositionLifetime = float4(position, lifetime);
    particle.velocitySeed = float4(0.0f, 0.0f, 0.0f, float(seed));
    particles[gid] = particle;
}

kernel void updateParticles(
    device GPUParticle* particles [[buffer(0)]],
    texture3d<half, access::sample> velocityTexture [[texture(0)]],
    constant GPUUniforms& u [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    uint activeCount = min(u.particleCounts.x, u.particleCounts.y);
    if (gid >= activeCount || gid >= u.particleCounts.y) return;

    GPUParticle particle = particles[gid];
    float3 position = particle.positionAge.xyz;
    float age = particle.positionAge.w;
    float lifetime = particle.previousPositionLifetime.w;
    float3 particleVelocity = particle.velocitySeed.xyz;
    float dt = max(u.deltaAndTime.x, 0.0f);
    float storedSeed = particle.velocitySeed.w;
    bool finiteSeed = isfinite(storedSeed)
        && abs(storedSeed) >= 1.0f
        && abs(storedSeed) <= float(0x00ffffffu);
    bool finiteParticle = all(isfinite(position))
        && isfinite(age)
        && isfinite(lifetime)
        && all(isfinite(particleVelocity))
        && finiteSeed;
    bool outsideDomain = any(abs(position) > 1.0f);
    uint seed = finiteSeed
        ? uint(abs(storedSeed))
        : ((particleHash(gid + 1u) & 0x00ffffffu) | 1u);
    if (finiteParticle && age < 0.0f) {
        float advancedAge = age + dt;
        if (advancedAge < 0.0f) {
            particle.positionAge.w = advancedAge;
            particle.previousPositionLifetime.w = max(u.particleBehavior.x, 0.5f);
            particles[gid] = particle;
        } else {
            particles[gid] = respawnParticle(seed, u);
        }
        return;
    }
    if (!finiteParticle || lifetime <= 0.0f || age >= lifetime || outsideDomain) {
        particles[gid] = recycleParticle(seed, gid, dt, activeCount, u);
        return;
    }

    constexpr sampler velocitySampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float3 coordinate = position * 0.5f + 0.5f;
    float3 fluidVelocity = float3(velocityTexture.sample(velocitySampler, coordinate).xyz);
    if (!all(isfinite(fluidVelocity))) fluidVelocity = float3(0.0f);
    float dragBlend = 1.0f - exp(-max(u.particleBehavior.w, 0.0f) * dt);
    particleVelocity = mix(particleVelocity, fluidVelocity, saturate(dragBlend));
    particleVelocity.y -= max(u.forces.x, 0.0f) * dt;
    float3 nextPosition = position + particleVelocity * dt;
    float nextAge = age + dt;

    bool invalidUpdate = !all(isfinite(nextPosition))
        || !all(isfinite(particleVelocity))
        || !isfinite(nextAge);
    if (invalidUpdate || nextAge >= lifetime || any(abs(nextPosition) > 1.0f)) {
        particles[gid] = recycleParticle(seed, gid, dt, activeCount, u);
        return;
    }

    particle.previousPositionLifetime.xyz = position;
    particle.positionAge = float4(nextPosition, nextAge);
    particle.velocitySeed.xyz = particleVelocity;
    particles[gid] = particle;
}
