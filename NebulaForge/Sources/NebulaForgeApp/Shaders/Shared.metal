#include <metal_stdlib>
using namespace metal;

struct GPUUniforms {
    uint4 gridSize;
    float4 deltaAndTime;
    float4 forces;
    float4 turbulence;
    float4 emitterPositionRadius;
    float4 emitterDirectionSpeed;
    uint4 particleCounts;
    float4 particleBehavior;
};

struct InteractionForce {
    float4 positionRadius;
    float4 directionStrength;
    uint4 modeAndPadding;
};

struct GPUParticle {
    float4 positionAge;
    float4 previousPositionLifetime;
    float4 velocitySeed;
};

struct ParticleRenderUniforms {
    float4x4 viewProjection;
    float4 viewportAndSize;
    uint4 paletteAndCount;
};

static_assert(sizeof(GPUUniforms) == 128, "GPUUniforms ABI must match Swift");
static_assert(sizeof(InteractionForce) == 48, "InteractionForce ABI must match Swift");
static_assert(sizeof(GPUParticle) == 48, "GPUParticle ABI must match Swift");
static_assert(sizeof(ParticleRenderUniforms) == 96, "ParticleRenderUniforms ABI must match Swift");

struct FullscreenOut { float4 position [[position]]; float2 uv; };

vertex FullscreenOut fullscreenVertex(uint id [[vertex_id]]) {
    const float2 p[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
    FullscreenOut out;
    out.position = float4(p[id], 0, 1);
    out.uv = p[id] * 0.5 + 0.5;
    return out;
}

fragment float4 diagnosticFragment(FullscreenOut in [[stage_in]]) {
    return float4(0.01 + 0.03 * in.uv.y, 0.005, 0.04 + 0.1 * in.uv.x, 1);
}
