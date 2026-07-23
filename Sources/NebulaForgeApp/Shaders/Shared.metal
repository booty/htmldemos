#include <metal_stdlib>
using namespace metal;

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
