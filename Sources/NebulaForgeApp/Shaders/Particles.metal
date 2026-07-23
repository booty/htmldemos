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
    constant GPUUniforms& u
) {
    float3 position = clamp(u.emitterPositionRadius.xyz, -1.0f, 1.0f);
    GPUParticle particle;
    // Negative age is a renderer-visible sentinel. Eligibility is recomputed
    // every update from absolute time and the current emission rate.
    particle.positionAge = float4(position, -1.0f);
    particle.previousPositionLifetime = float4(
        position,
        max(u.particleBehavior.x, 0.5f)
    );
    particle.velocitySeed = float4(0.0f, 0.0f, 0.0f, float(seed));
    return particle;
}

static float emissionCycle(
    uint activeCount,
    constant GPUUniforms& u
) {
    float rate = max(u.particleBehavior.z, 1.0f);
    return float(max(activeCount, 1u)) / rate;
}

static float emissionPhase(
    uint seed,
    uint particleIndex,
    constant GPUUniforms& u
) {
    float rate = max(u.particleBehavior.z, 1.0f);
    return (
        float(particleIndex) + particleRandom(seed ^ 0x85ebca6bu)
    ) / rate;
}

static float nextEmissionTimeAfter(
    uint seed,
    uint particleIndex,
    uint activeCount,
    float time,
    constant GPUUniforms& u
) {
    float cycle = emissionCycle(activeCount, u);
    float phase = emissionPhase(seed, particleIndex, u);
    float cycleIndex = floor((time - phase) / cycle) + 1.0f;
    float eventTime = phase + cycleIndex * cycle;
    if (eventTime <= time) eventTime += cycle;
    return eventTime;
}

static GPUParticle integrateParticle(
    GPUParticle particle,
    float duration,
    uint seed,
    texture3d<half, access::sample> velocityTexture,
    constant GPUUniforms& u
) {
    if (duration <= 0.0f) return particle;

    float3 position = particle.positionAge.xyz;
    float age = particle.positionAge.w;
    float lifetime = particle.previousPositionLifetime.w;
    float3 particleVelocity = particle.velocitySeed.xyz;
    constexpr sampler velocitySampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float3 coordinate = position * 0.5f + 0.5f;
    float3 fluidVelocity = float3(velocityTexture.sample(velocitySampler, coordinate).xyz);
    if (!all(isfinite(fluidVelocity))) fluidVelocity = float3(0.0f);
    float dragBlend = 1.0f - exp(-max(u.particleBehavior.w, 0.0f) * duration);
    particleVelocity = mix(particleVelocity, fluidVelocity, saturate(dragBlend));
    particleVelocity.y -= max(u.forces.x, 0.0f) * duration;
    float3 nextPosition = position + particleVelocity * duration;
    float nextAge = age + duration;

    bool invalidUpdate = !all(isfinite(nextPosition))
        || !all(isfinite(particleVelocity))
        || !isfinite(nextAge);
    if (invalidUpdate || nextAge >= lifetime || any(abs(nextPosition) > 1.0f)) {
        return dormantParticle(seed, u);
    }

    particle.previousPositionLifetime.xyz = position;
    particle.positionAge = float4(nextPosition, nextAge);
    particle.velocitySeed.xyz = particleVelocity;
    return particle;
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

    GPUParticle particle;
    particle.positionAge = float4(position, -1.0f);
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
    float intervalEnd = max(u.deltaAndTime.y, 0.0f);
    float intervalStart = max(intervalEnd - dt, 0.0f);
    if (finiteParticle && age < 0.0f) {
        float eventTime = nextEmissionTimeAfter(
            seed,
            gid,
            activeCount,
            intervalStart,
            u
        );
        if (eventTime <= intervalEnd) {
            GPUParticle respawned = respawnParticle(seed, u);
            particles[gid] = integrateParticle(
                respawned,
                intervalEnd - eventTime,
                seed,
                velocityTexture,
                u
            );
        } else {
            particle.positionAge.w = -1.0f;
            particle.previousPositionLifetime.w = max(u.particleBehavior.x, 0.5f);
            particles[gid] = particle;
        }
        return;
    }
    if (!finiteParticle || lifetime <= 0.0f || age >= lifetime || outsideDomain) {
        particles[gid] = dormantParticle(seed, u);
        return;
    }

    float deathOffset = lifetime - age;
    if (deathOffset <= dt) {
        float deathTime = intervalStart + max(deathOffset, 0.0f);
        float cycle = emissionCycle(activeCount, u);
        float respawnTime = cycle <= lifetime
            ? deathTime
            : nextEmissionTimeAfter(seed, gid, activeCount, deathTime, u);
        if (respawnTime <= intervalEnd) {
            GPUParticle respawned = respawnParticle(seed, u);
            // Production dt is at most 1/60 and validated lifetime is at least
            // 0.5 seconds, so one expiry/respawn event per update is sufficient.
            particles[gid] = integrateParticle(
                respawned,
                intervalEnd - respawnTime,
                seed,
                velocityTexture,
                u
            );
            return;
        }
        particles[gid] = dormantParticle(seed, u);
        return;
    }

    particles[gid] = integrateParticle(
        particle,
        dt,
        seed,
        velocityTexture,
        u
    );
}

struct ParticleVertexOut {
    float4 position [[position]];
    float2 spriteUV;
    float speed;
    float ageFraction;
    float depth;
    float velocityColorMix;
    uint paletteIndex [[flat]];
    float active [[flat]];
};

static float3 paletteColor(
    float speed,
    float ageFraction,
    uint paletteIndex,
    float velocityColorMix
) {
    float palettePosition = saturate(mix(
        1.0f - ageFraction,
        speed,
        velocityColorMix
    ));
    float3 low;
    float3 middle;
    float3 high;

    switch (min(paletteIndex, 3u)) {
    case 1u:
        low = float3(0.05f, 0.35f, 0.65f);
        middle = float3(0.10f, 1.75f, 1.20f);
        high = float3(1.35f, 0.45f, 2.50f);
        break;
    case 2u:
        low = float3(0.15f, 0.20f, 1.20f);
        middle = float3(2.20f, 0.20f, 0.45f);
        high = float3(4.00f, 2.20f, 0.55f);
        break;
    case 3u:
        low = float3(0.03f, 0.02f, 0.20f);
        middle = float3(0.35f, 0.08f, 1.20f);
        high = float3(1.60f, 0.35f, 2.80f);
        break;
    default:
        low = float3(0.35f, 0.04f, 0.02f);
        middle = float3(2.20f, 0.35f, 0.03f);
        high = float3(4.00f, 2.40f, 0.55f);
        break;
    }

    float3 color = palettePosition < 0.5f
        ? mix(low, middle, smoothstep(0.0f, 0.5f, palettePosition))
        : mix(middle, high, smoothstep(0.5f, 1.0f, palettePosition));
    return color * mix(0.75f, 1.35f, speed);
}

vertex ParticleVertexOut particleVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device const GPUParticle* particles [[buffer(0)]],
    constant ParticleRenderUniforms& u [[buffer(1)]]
) {
    ParticleVertexOut out;
    out.position = float4(2.0f, 2.0f, 2.0f, 1.0f);
    out.spriteUV = float2(0.0f);
    out.speed = 0.0f;
    out.ageFraction = 1.0f;
    out.depth = 1.0f;
    out.velocityColorMix = saturate(u.viewportAndSize.w);
    out.paletteIndex = min(u.paletteAndCount.x, 3u);
    out.active = 0.0f;

    if (instanceID >= u.paletteAndCount.y) return out;
    GPUParticle particle = particles[instanceID];
    float age = particle.positionAge.w;
    float lifetime = particle.previousPositionLifetime.w;
    bool finiteParticle = all(isfinite(particle.positionAge))
        && all(isfinite(particle.previousPositionLifetime))
        && all(isfinite(particle.velocitySeed));
    if (!finiteParticle || age < 0.0f || lifetime <= 0.0f || age >= lifetime) {
        return out;
    }

    float4 currentClip = u.viewProjection * float4(particle.positionAge.xyz, 1.0f);
    float4 previousClip = u.viewProjection
        * float4(particle.previousPositionLifetime.xyz, 1.0f);
    if (
        !all(isfinite(currentClip))
        || !all(isfinite(previousClip))
        || currentClip.w <= 1.0e-5f
        || previousClip.w <= 1.0e-5f
    ) {
        return out;
    }

    float2 viewport = max(u.viewportAndSize.xy, float2(1.0f));
    float2 currentNDC = currentClip.xy / currentClip.w;
    float2 previousNDC = previousClip.xy / previousClip.w;
    float2 projectedDeltaPixels = (currentNDC - previousNDC) * viewport * 0.5f;
    float projectedLength = length(projectedDeltaPixels);
    float2 tangent = projectedLength > 1.0e-5f
        ? projectedDeltaPixels / projectedLength
        : float2(0.0f, 1.0f);
    float2 normal = float2(-tangent.y, tangent.x);
    float speed = saturate(length(particle.velocitySeed.xyz) / 4.0f);
    float spriteSize = max(u.viewportAndSize.z, 0.25f);
    float streakLength = spriteSize * mix(1.5f, 8.0f, speed)
        + min(projectedLength, spriteSize * 4.0f);
    const float2 corners[4] = {
        float2(-1.0f, -1.0f),
        float2( 1.0f, -1.0f),
        float2(-1.0f,  1.0f),
        float2( 1.0f,  1.0f)
    };
    float2 corner = corners[vertexID];
    float alongPixels = (corner.x - 1.0f) * 0.5f * streakLength;
    float acrossPixels = corner.y * spriteSize * 0.5f;
    float2 ndcOffset = (
        tangent * alongPixels + normal * acrossPixels
    ) * 2.0f / viewport;

    out.position = currentClip;
    out.position.xy += ndcOffset * currentClip.w;
    out.spriteUV = corner;
    out.speed = speed;
    out.ageFraction = saturate(age / lifetime);
    out.depth = currentClip.z / currentClip.w;
    out.active = 1.0f;
    return out;
}

fragment half4 particleFragment(ParticleVertexOut in [[stage_in]]) {
    if (in.active < 0.5f) discard_fragment();
    float r2 = dot(in.spriteUV, in.spriteUV);
    if (r2 >= 1.0f) discard_fragment();
    float alpha = smoothstep(1.0f, 0.1f, r2)
        * (1.0f - 0.35f * in.ageFraction);
    float3 color = paletteColor(
        in.speed,
        in.ageFraction,
        in.paletteIndex,
        in.velocityColorMix
    );
    return half4(half3(color * alpha), half(alpha));
}

fragment half4 particleDisplayFragment(
    FullscreenOut in [[stage_in]],
    texture2d<half, access::sample> hdrTexture [[texture(0)]]
) {
    constexpr sampler displaySampler(
        coord::normalized,
        address::clamp_to_edge,
        filter::linear
    );
    half3 hdrColor = max(
        hdrTexture.sample(displaySampler, in.uv).rgb,
        half3(0.0h)
    );
    // Task 8 replaces this display-only clamp with bloom and tone mapping.
    half3 background = half3(0.01h, 0.005h, 0.04h);
    return half4(min(hdrColor + background, half3(1.0h)), 1.0h);
}
