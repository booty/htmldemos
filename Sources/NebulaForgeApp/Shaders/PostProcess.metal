#include <metal_stdlib>
using namespace metal;

struct PostProcessUniforms {
    uint4 sourceAndBloomSize;
    uint4 destinationAndBlur;
    float4 appearance;
    float4 backgroundAndPadding;
};

static float3 finiteHDR(float3 value) {
    return all(isfinite(value))
        ? clamp(value, float3(0.0f), float3(60000.0f))
        : float3(0.0f);
}

static uint2 clampedCoordinate(int2 coordinate, uint width, uint height) {
    return uint2(clamp(
        coordinate,
        int2(0),
        int2(int(max(width, 1u)) - 1, int(max(height, 1u)) - 1)
    ));
}

static uint2 scaledCoordinate(
    uint2 outputCoordinate,
    uint2 outputSize,
    uint2 inputSize
) {
    float2 centered = float2(outputCoordinate) + 0.5f;
    float2 scaled = centered * float2(inputSize) / float2(max(outputSize, uint2(1)));
    return clampedCoordinate(int2(scaled), inputSize.x, inputSize.y);
}

static float3 aces(float3 x) {
    const float a = 2.51f;
    const float b = 0.03f;
    const float c = 2.43f;
    const float d = 0.59f;
    const float e = 0.14f;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

kernel void clearPostProcessTexture(
    texture2d<half, access::write> output [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    output.write(half4(0.0h), gid);
}

kernel void accumulateTrails(
    texture2d<half, access::read> source [[texture(0)]],
    texture2d<half, access::read> previousTrail [[texture(1)]],
    texture2d<half, access::write> output [[texture(2)]],
    constant PostProcessUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;

    uint2 sourceCoordinate = clampedCoordinate(
        int2(gid),
        source.get_width(),
        source.get_height()
    );
    uint2 historyCoordinate = clampedCoordinate(
        int2(gid),
        previousTrail.get_width(),
        previousTrail.get_height()
    );
    float4 current = float4(source.read(sourceCoordinate));
    float4 previous = float4(previousTrail.read(historyCoordinate));
    float persistence = clamp(u.appearance.x, 0.0f, 0.98f);
    float3 accumulated = finiteHDR(max(
        finiteHDR(current.rgb),
        finiteHDR(previous.rgb) * persistence
    ));
    float alpha = clamp(max(current.a, previous.a * persistence), 0.0f, 1.0f);
    output.write(half4(half3(accumulated), half(alpha)), gid);
}

kernel void extractBloom(
    texture2d<half, access::read> source [[texture(0)]],
    texture2d<half, access::write> output [[texture(1)]],
    constant PostProcessUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;

    int2 base = int2(gid * 2u);
    float3 color = float3(0.0f);
    color += finiteHDR(float3(source.read(clampedCoordinate(
        base,
        source.get_width(),
        source.get_height()
    )).rgb));
    color += finiteHDR(float3(source.read(clampedCoordinate(
        base + int2(1, 0),
        source.get_width(),
        source.get_height()
    )).rgb));
    color += finiteHDR(float3(source.read(clampedCoordinate(
        base + int2(0, 1),
        source.get_width(),
        source.get_height()
    )).rgb));
    color += finiteHDR(float3(source.read(clampedCoordinate(
        base + int2(1, 1),
        source.get_width(),
        source.get_height()
    )).rgb));
    color *= 0.25f;

    float brightness = max(color.r, max(color.g, color.b));
    float contribution = brightness > 0.75f
        ? (brightness - 0.75f) / max(brightness, 1.0e-5f)
        : 0.0f;
    output.write(half4(half3(finiteHDR(color * contribution)), 1.0h), gid);
}

kernel void blurHorizontal(
    texture2d<half, access::read> source [[texture(0)]],
    texture2d<half, access::write> output [[texture(1)]],
    constant PostProcessUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;

    int radius = int(min(u.destinationAndBlur.z, 12u));
    if (radius == 0) {
        uint2 coordinate = clampedCoordinate(
            int2(gid),
            source.get_width(),
            source.get_height()
        );
        output.write(source.read(coordinate), gid);
        return;
    }

    float sigma = max(float(radius) * 0.5f, 0.5f);
    float3 sum = float3(0.0f);
    float weightSum = 0.0f;
    for (int offset = -12; offset <= 12; ++offset) {
        if (abs(offset) > radius) continue;
        float weight = exp(-0.5f * float(offset * offset) / (sigma * sigma));
        uint2 coordinate = clampedCoordinate(
            int2(gid) + int2(offset, 0),
            source.get_width(),
            source.get_height()
        );
        sum += finiteHDR(float3(source.read(coordinate).rgb)) * weight;
        weightSum += weight;
    }
    output.write(half4(half3(finiteHDR(sum / max(weightSum, 1.0e-5f))), 1.0h), gid);
}

kernel void blurVertical(
    texture2d<half, access::read> source [[texture(0)]],
    texture2d<half, access::write> output [[texture(1)]],
    constant PostProcessUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;

    int radius = int(min(u.destinationAndBlur.z, 12u));
    if (radius == 0) {
        uint2 coordinate = clampedCoordinate(
            int2(gid),
            source.get_width(),
            source.get_height()
        );
        output.write(source.read(coordinate), gid);
        return;
    }

    float sigma = max(float(radius) * 0.5f, 0.5f);
    float3 sum = float3(0.0f);
    float weightSum = 0.0f;
    for (int offset = -12; offset <= 12; ++offset) {
        if (abs(offset) > radius) continue;
        float weight = exp(-0.5f * float(offset * offset) / (sigma * sigma));
        uint2 coordinate = clampedCoordinate(
            int2(gid) + int2(0, offset),
            source.get_width(),
            source.get_height()
        );
        sum += finiteHDR(float3(source.read(coordinate).rgb)) * weight;
        weightSum += weight;
    }
    output.write(half4(half3(finiteHDR(sum / max(weightSum, 1.0e-5f))), 1.0h), gid);
}

kernel void compositeToneMap(
    texture2d<half, access::read> trail [[texture(0)]],
    texture2d<half, access::read> bloom [[texture(1)]],
    texture2d<float, access::read> depth [[texture(2)]],
    texture2d<half, access::write> output [[texture(3)]],
    constant PostProcessUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;

    uint2 outputSize = uint2(output.get_width(), output.get_height());
    uint2 trailCoordinate = scaledCoordinate(
        gid,
        outputSize,
        uint2(trail.get_width(), trail.get_height())
    );
    uint2 bloomCoordinate = scaledCoordinate(
        gid,
        outputSize,
        uint2(bloom.get_width(), bloom.get_height())
    );
    uint2 depthCoordinate = scaledCoordinate(
        gid,
        outputSize,
        uint2(depth.get_width(), depth.get_height())
    );

    float3 trailColor = finiteHDR(float3(trail.read(trailCoordinate).rgb));
    float3 bloomColor = finiteHDR(float3(bloom.read(bloomCoordinate).rgb));
    float sceneDepth = clamp(depth.read(depthCoordinate).r, 0.0f, 1.0f);
    if (!isfinite(sceneDepth)) sceneDepth = 1.0f;

    float backgroundIntensity = clamp(u.backgroundAndPadding.x, 0.0f, 0.4f);
    float3 background = float3(0.22f, 0.035f, 0.45f) * backgroundIntensity;
    float fogAmount = clamp(u.appearance.z, 0.0f, 1.0f)
        * smoothstep(0.15f, 1.0f, sceneDepth);
    float3 fogColor = float3(0.055f, 0.075f, 0.18f)
        * (0.15f + backgroundIntensity);
    float3 foggedTrail = mix(trailColor, fogColor, fogAmount * 0.65f);
    float bloomIntensity = clamp(u.appearance.y, 0.0f, 3.0f);
    float3 hdr = finiteHDR(background + foggedTrail + bloomColor * bloomIntensity);
    float exposure = exp2(clamp(u.appearance.w, -4.0f, 4.0f));
    float3 mapped = aces(finiteHDR(hdr * exposure));
    output.write(half4(half3(mapped), 1.0h), gid);
}
