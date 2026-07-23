#include <metal_stdlib>
using namespace metal;

static uint3 clampedCell(int3 cell, uint3 size) {
    return uint3(clamp(cell, int3(0), int3(size) - 1));
}

static float3 velocityAt(
    texture3d<half, access::read> velocity,
    int3 cell,
    uint3 size
) {
    return float3(velocity.read(clampedCell(cell, size)).xyz);
}

static float scalarAt(
    texture3d<half, access::read> scalar,
    int3 cell,
    uint3 size
) {
    return float(scalar.read(clampedCell(cell, size)).x);
}

static float3 curlAt(
    texture3d<half, access::read> velocity,
    int3 cell,
    uint3 size
) {
    float3 left = velocityAt(velocity, cell + int3(-1, 0, 0), size);
    float3 right = velocityAt(velocity, cell + int3(1, 0, 0), size);
    float3 down = velocityAt(velocity, cell + int3(0, -1, 0), size);
    float3 up = velocityAt(velocity, cell + int3(0, 1, 0), size);
    float3 back = velocityAt(velocity, cell + int3(0, 0, -1), size);
    float3 front = velocityAt(velocity, cell + int3(0, 0, 1), size);

    return 0.5f * float3(
        (up.z - down.z) - (front.y - back.y),
        (front.x - back.x) - (right.z - left.z),
        (right.y - left.y) - (up.x - down.x)
    );
}

static float3 boundedVelocity(float3 velocity) {
    constexpr float maximumSpeed = 64.0f;
    float speed = length(velocity);
    return speed > maximumSpeed ? velocity * (maximumSpeed / speed) : velocity;
}

kernel void injectForces(
    texture3d<half, access::read> input [[texture(0)]],
    texture3d<half, access::write> output [[texture(1)]],
    constant GPUUniforms& u [[buffer(0)]],
    constant InteractionForce& force [[buffer(1)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (any(gid >= u.gridSize.xyz)) return;

    float dt = u.deltaAndTime.x;
    float3 position = ((float3(gid) + 0.5f) / float3(u.gridSize.xyz)) * 2.0f - 1.0f;
    float3 velocity = float3(input.read(gid).xyz);

    float3 emitterOffset = position - u.emitterPositionRadius.xyz;
    float emitterRadius = max(u.emitterPositionRadius.w, 1.0e-4f);
    float emitterWeight = smoothstep(emitterRadius, 0.0f, length(emitterOffset));
    velocity += u.emitterDirectionSpeed.xyz * u.emitterDirectionSpeed.w * emitterWeight * dt;

    velocity.y -= u.forces.x * dt;
    float radius = max(length(position), 1.0e-4f);
    velocity += (-position / radius) * u.forces.y * dt * smoothstep(1.75f, 0.0f, radius);
    velocity += cross(float3(0.0f, 1.0f, 0.0f), position / radius)
        * u.forces.z * dt * smoothstep(1.75f, 0.0f, radius);

    float noise = sin(dot(position * u.turbulence.x, float3(12.9898f, 78.233f, 37.719f))
        + u.deltaAndTime.y * 1.7f);
    velocity += float3(noise, sin(noise * 2.31f), cos(noise * 1.73f))
        * u.turbulence.y * dt * 0.1f;

    float interactionRadius = force.positionRadius.w;
    float3 interactionOffset = force.positionRadius.xyz - position;
    float interactionDistance = length(interactionOffset);
    if (interactionRadius > 0.0f && interactionDistance < interactionRadius) {
        float weight = 1.0f - interactionDistance / interactionRadius;
        float3 direction = interactionOffset / max(interactionDistance, 1.0e-4f);
        uint mode = force.modeAndPadding.x;
        if (mode == 2u) direction = -direction;
        if (mode == 3u) {
            float3 axis = normalize(force.directionStrength.xyz + float3(0.0f, 1.0e-4f, 0.0f));
            direction = cross(axis, direction);
        }
        if (mode >= 1u && mode <= 3u) {
            velocity += direction * force.directionStrength.w * weight * dt;
        }
    }

    output.write(half4(half3(boundedVelocity(velocity)), half(0.0f)), gid);
}

kernel void advectVelocity(
    texture3d<half, access::sample> input [[texture(0)]],
    texture3d<half, access::write> output [[texture(1)]],
    constant GPUUniforms& u [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (any(gid >= u.gridSize.xyz)) return;

    constexpr sampler velocitySampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float3 size = float3(u.gridSize.xyz);
    float3 coordinate = (float3(gid) + 0.5f) / size;
    float3 current = float3(input.sample(velocitySampler, coordinate).xyz);
    float3 traced = coordinate - current * u.deltaAndTime.x * 0.5f;
    float3 velocity = float3(input.sample(velocitySampler, traced).xyz);

    float cellStep = 1.0f / size.x;
    float3 average = (
        float3(input.sample(velocitySampler, coordinate + float3(cellStep, 0.0f, 0.0f)).xyz)
        + float3(input.sample(velocitySampler, coordinate - float3(cellStep, 0.0f, 0.0f)).xyz)
        + float3(input.sample(velocitySampler, coordinate + float3(0.0f, cellStep, 0.0f)).xyz)
        + float3(input.sample(velocitySampler, coordinate - float3(0.0f, cellStep, 0.0f)).xyz)
        + float3(input.sample(velocitySampler, coordinate + float3(0.0f, 0.0f, cellStep)).xyz)
        + float3(input.sample(velocitySampler, coordinate - float3(0.0f, 0.0f, cellStep)).xyz)
    ) / 6.0f;
    float viscosityBlend = saturate(u.deltaAndTime.w * u.deltaAndTime.x * size.x);
    velocity = mix(velocity, average, viscosityBlend);
    velocity *= exp(-u.deltaAndTime.z * u.deltaAndTime.x);

    output.write(half4(half3(boundedVelocity(velocity)), half(0.0f)), gid);
}

kernel void applyVorticity(
    texture3d<half, access::read> input [[texture(0)]],
    texture3d<half, access::write> output [[texture(1)]],
    constant GPUUniforms& u [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (any(gid >= u.gridSize.xyz)) return;

    int3 cell = int3(gid);
    uint3 size = u.gridSize.xyz;
    float3 curl = curlAt(input, cell, size);
    float3 gradient = 0.5f * float3(
        length(curlAt(input, cell + int3(1, 0, 0), size))
            - length(curlAt(input, cell + int3(-1, 0, 0), size)),
        length(curlAt(input, cell + int3(0, 1, 0), size))
            - length(curlAt(input, cell + int3(0, -1, 0), size)),
        length(curlAt(input, cell + int3(0, 0, 1), size))
            - length(curlAt(input, cell + int3(0, 0, -1), size))
    );
    float3 normal = gradient / max(length(gradient), 1.0e-4f);
    float3 velocity = float3(input.read(gid).xyz);
    velocity += cross(normal, curl) * u.forces.w * u.deltaAndTime.x;
    output.write(half4(half3(boundedVelocity(velocity)), half(0.0f)), gid);
}

kernel void computeDivergence(
    texture3d<half, access::read> velocity [[texture(0)]],
    texture3d<half, access::write> divergence [[texture(1)]],
    constant GPUUniforms& u [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (any(gid >= u.gridSize.xyz)) return;

    int3 cell = int3(gid);
    uint3 size = u.gridSize.xyz;
    float value = 0.5f * (
        velocityAt(velocity, cell + int3(1, 0, 0), size).x
        - velocityAt(velocity, cell + int3(-1, 0, 0), size).x
        + velocityAt(velocity, cell + int3(0, 1, 0), size).y
        - velocityAt(velocity, cell + int3(0, -1, 0), size).y
        + velocityAt(velocity, cell + int3(0, 0, 1), size).z
        - velocityAt(velocity, cell + int3(0, 0, -1), size).z
    );
    divergence.write(half4(half(value), half(0.0f), half(0.0f), half(0.0f)), gid);
}

kernel void jacobiPressure(
    texture3d<half, access::read> pressureIn [[texture(0)]],
    texture3d<half, access::read> divergence [[texture(1)]],
    texture3d<half, access::write> pressureOut [[texture(2)]],
    constant GPUUniforms& u [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (any(gid >= u.gridSize.xyz)) return;

    int3 cell = int3(gid);
    uint3 size = u.gridSize.xyz;
    float neighbors =
        scalarAt(pressureIn, cell + int3(1, 0, 0), size)
        + scalarAt(pressureIn, cell + int3(-1, 0, 0), size)
        + scalarAt(pressureIn, cell + int3(0, 1, 0), size)
        + scalarAt(pressureIn, cell + int3(0, -1, 0), size)
        + scalarAt(pressureIn, cell + int3(0, 0, 1), size)
        + scalarAt(pressureIn, cell + int3(0, 0, -1), size);
    float pressure = (neighbors - scalarAt(divergence, cell, size)) / 6.0f;
    pressureOut.write(half4(half(pressure), half(0.0f), half(0.0f), half(0.0f)), gid);
}

kernel void subtractPressureGradient(
    texture3d<half, access::read> velocityIn [[texture(0)]],
    texture3d<half, access::read> pressure [[texture(1)]],
    texture3d<half, access::write> velocityOut [[texture(2)]],
    constant GPUUniforms& u [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (any(gid >= u.gridSize.xyz)) return;

    int3 cell = int3(gid);
    uint3 size = u.gridSize.xyz;
    float3 gradient = 0.5f * float3(
        scalarAt(pressure, cell + int3(1, 0, 0), size)
            - scalarAt(pressure, cell + int3(-1, 0, 0), size),
        scalarAt(pressure, cell + int3(0, 1, 0), size)
            - scalarAt(pressure, cell + int3(0, -1, 0), size),
        scalarAt(pressure, cell + int3(0, 0, 1), size)
            - scalarAt(pressure, cell + int3(0, 0, -1), size)
    );
    float3 velocity = float3(velocityIn.read(gid).xyz) - gradient;
    velocityOut.write(half4(half3(boundedVelocity(velocity)), half(0.0f)), gid);
}

kernel void clearFluid(
    texture3d<half, access::write> velocity [[texture(0)]],
    texture3d<half, access::write> scalar [[texture(1)]],
    constant GPUUniforms& u [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (any(gid >= u.gridSize.xyz)) return;
    velocity.write(half4(half(0.0f)), gid);
    scalar.write(half4(half(0.0f)), gid);
}

kernel void reduceFiniteDiagnostic(
    texture3d<half, access::read> velocity [[texture(0)]],
    device atomic_uint& flag [[buffer(0)]],
    constant GPUUniforms& u [[buffer(1)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (any(gid >= u.gridSize.xyz)) return;
    float3 value = float3(velocity.read(gid).xyz);
    if (!all(isfinite(value))) {
        atomic_store_explicit(&flag, 0u, memory_order_relaxed);
    }
}
