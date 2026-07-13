#include <metal_stdlib>
using namespace metal;

// Environment uniforms available to per-preset custom shaders — the subset of
// MilkDrop's shader environment the engine currently feeds.
struct PresetEnv {
    float4 texsize;    // w, h, 1/w, 1/h of the internal buffer
    float4 blurScale;  // scale1..3 un-mapping for blur samplers (w unused)
    float4 blurBias;   // bias1..3 (w unused)
    float4 outputMix;  // x = brightness, y = saturation (display-only mute)
};

// Display-only output mute: clamp first so peak whites actually dim (instead
// of staying clipped), pull toward luma for the saturation cut, then scale.
// Composite pass ONLY — muting inside the feedback loop would compound every
// frame and kill the trails.
static inline float3 applyOutputMix(float3 c, float brightness, float saturation) {
    c = saturate(c);
    float luma = dot(c, float3(0.299, 0.587, 0.114));
    return mix(float3(luma), c, saturation) * brightness;
}

// ---------- Warp pass: draw the mesh, sampling the previous frame ----------

struct WarpUniforms {
    float decay;
};

struct WarpVOut {
    float4 position [[position]];
    float2 uv;
};

vertex WarpVOut warp_vertex(uint vid [[vertex_id]],
                            const device float2 *positions [[buffer(0)]],
                            const device float2 *uvs [[buffer(1)]]) {
    WarpVOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = uvs[vid];
    return out;
}

fragment float4 warp_fragment(WarpVOut in [[stage_in]],
                              texture2d<float> prev [[texture(0)]],
                              constant WarpUniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float3 c = prev.sample(s, in.uv).rgb * u.decay;
    return float4(c, 1.0);
}

// ---------- Waveform: line strip with per-vertex color ----------

struct WaveVOut {
    float4 position [[position]];
    float4 color;
};

vertex WaveVOut wave_vertex(uint vid [[vertex_id]],
                            const device float2 *points [[buffer(0)]],
                            const device float4 *colors [[buffer(1)]],
                            constant float2 &thickOffset [[buffer(2)]]) {
    WaveVOut out;
    out.position = float4(points[vid] + thickOffset, 0.0, 1.0);
    out.color = colors[vid];
    return out;
}

fragment float4 wave_fragment(WaveVOut in [[stage_in]]) {
    return in.color;
}

// ---------- Custom shape: textured triangle fan ----------

struct ShapeVOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex ShapeVOut shape_vertex(uint vid [[vertex_id]],
                              const device float2 *points [[buffer(0)]],
                              const device float2 *uvs [[buffer(1)]],
                              const device float4 *colors [[buffer(2)]]) {
    ShapeVOut out;
    out.position = float4(points[vid], 0.0, 1.0);
    out.uv = uvs[vid];
    out.color = colors[vid];
    return out;
}

fragment float4 shape_textured_fragment(ShapeVOut in [[stage_in]],
                                        texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float3 c = tex.sample(s, in.uv).rgb * in.color.rgb;
    return float4(c, in.color.a);
}

fragment float4 shape_flat_fragment(ShapeVOut in [[stage_in]]) {
    return in.color;
}

// ---------- Fullscreen helpers ----------

struct CompVOut {
    float4 position [[position]];
    float2 uv;
};

// Fullscreen triangle from vertex_id — no buffers needed.
vertex CompVOut comp_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid == 1) ? 3.0 : -1.0, (vid == 2) ? 3.0 : -1.0);
    CompVOut out;
    out.position = float4(pos, 0.0, 1.0);
    out.uv = float2(pos.x * 0.5 + 0.5, 0.5 - pos.y * 0.5);
    return out;
}

// ---------- Composite pass (default) ----------

struct CompUniforms {
    float4 gbs; // gamma, brightness, saturation, unused
};

fragment float4 comp_fragment(CompVOut in [[stage_in]],
                              texture2d<float> tex [[texture(0)]],
                              constant CompUniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float3 c = tex.sample(s, in.uv).rgb;
    // MilkDrop's gamma is a brightness lift on the (dim, decaying) internal
    // buffer, not a display transfer curve.
    c = c * u.gbs.x;
    c = applyOutputMix(c, u.gbs.y, u.gbs.z);
    return float4(c, 1.0);
}

// ---------- Blur pyramid (port of butterchurn BlurHorizontal/BlurVertical) ----------

struct BlurHUniforms {
    float4 texsize;
    float4 ws;
    float4 ds;
    float4 scaleBiasWdiv; // scale, bias, wdiv, unused
};

fragment float4 blur_h_fragment(CompVOut in [[stage_in]],
                                texture2d<float> tex [[texture(0)]],
                                constant BlurHUniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 uv = in.uv;
    float3 blur =
        (tex.sample(s, uv + float2( u.ds.x * u.texsize.z, 0.0)).rgb
       + tex.sample(s, uv + float2(-u.ds.x * u.texsize.z, 0.0)).rgb) * u.ws.x +
        (tex.sample(s, uv + float2( u.ds.y * u.texsize.z, 0.0)).rgb
       + tex.sample(s, uv + float2(-u.ds.y * u.texsize.z, 0.0)).rgb) * u.ws.y +
        (tex.sample(s, uv + float2( u.ds.z * u.texsize.z, 0.0)).rgb
       + tex.sample(s, uv + float2(-u.ds.z * u.texsize.z, 0.0)).rgb) * u.ws.z +
        (tex.sample(s, uv + float2( u.ds.w * u.texsize.z, 0.0)).rgb
       + tex.sample(s, uv + float2(-u.ds.w * u.texsize.z, 0.0)).rgb) * u.ws.w;
    blur *= u.scaleBiasWdiv.z;
    blur = blur * u.scaleBiasWdiv.x + u.scaleBiasWdiv.y;
    return float4(blur, 1.0);
}

struct BlurVUniforms {
    float4 texsize;
    float4 wds;    // w1, w2, d1, d2
    float4 edWdiv; // ed1, ed2, ed3, wdiv
};

fragment float4 blur_v_fragment(CompVOut in [[stage_in]],
                                texture2d<float> tex [[texture(0)]],
                                constant BlurVUniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 uv = in.uv;
    float3 blur =
        (tex.sample(s, uv + float2(0.0,  u.wds.z * u.texsize.w)).rgb
       + tex.sample(s, uv + float2(0.0, -u.wds.z * u.texsize.w)).rgb) * u.wds.x +
        (tex.sample(s, uv + float2(0.0,  u.wds.w * u.texsize.w)).rgb
       + tex.sample(s, uv + float2(0.0, -u.wds.w * u.texsize.w)).rgb) * u.wds.y;
    blur *= u.edWdiv.w;
    // Edge darken (b1ed): fades the blur toward frame edges on level 1.
    float t = min(min(uv.x, uv.y), 1.0 - max(uv.x, uv.y));
    t = sqrt(t);
    t = u.edWdiv.x + u.edWdiv.y * clamp(t * u.edWdiv.z, 0.0, 1.0);
    blur *= t;
    return float4(blur, 1.0);
}

// ---------- Preset: $$$ Royal - Mashup (197) ----------
// Hand-translated from the preset pack's converted GLSL (machine-generated
// three-address code; structure kept 1:1 with the original, quirks included).

fragment float4 mashup197_warp_fragment(WarpVOut in [[stage_in]],
                                        texture2d<float> sampler_main [[texture(0)]],
                                        constant PresetEnv &env [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 uv = in.uv;
    // Original uses texsize.z (1/w) for BOTH axis offsets — preset quirk, kept.
    float2 t2 = float2(1.0, 0.0) * env.texsize.z;
    float2 t3 = float2(0.0, 1.0) * env.texsize.z;
    float3 ret = ((sampler_main.sample(s, uv + t2).rgb + sampler_main.sample(s, uv + t2).rgb) * 0.5
                + (sampler_main.sample(s, uv + t3).rgb + sampler_main.sample(s, uv + t3).rgb) * 0.5)
                - sampler_main.sample(s, (uv - 0.5) * 0.9 + 0.5).rgb;
    ret = ret - 0.4;
    return float4(ret, 1.0);
}

fragment float4 mashup197_comp_fragment(CompVOut in [[stage_in]],
                                        texture2d<float> sampler_main [[texture(0)]],
                                        texture2d<float> sampler_blur3 [[texture(1)]],
                                        constant PresetEnv &env [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 uv = in.uv;
    float2 uv2 = (0.5 - uv) + 0.5; // 180° mirror
    float3 ret = mix(sampler_main.sample(s, uv).rgb,
                     sampler_main.sample(s, uv2).rgb,
                     float3(0.5)) * 2.0;
    ret = (((sampler_blur3.sample(s, uv).rgb * env.blurScale.z) + env.blurBias.z) * 2.0
         + ((sampler_blur3.sample(s, uv2).rgb * env.blurScale.z) + env.blurBias.z) * 2.0) + ret;
    ret = applyOutputMix(ret, env.outputMix.x, env.outputMix.y);
    return float4(ret, 1.0);
}
