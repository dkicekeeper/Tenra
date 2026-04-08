//
//  SiriWaveShader.metal
//  Tenra
//
//  Apple Intelligence–style edge glow shader.
//  Renders an animated angular gradient around the screen border that
//  pulses with microphone amplitude, replicating the iOS 18 Siri glow.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Types

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct WaveUniforms {
    float time;
    float amplitude;
    float resW;
    float resH;
    float cornerR;   // device corner radius in pixels
};

// MARK: - Vertex shader (full-screen triangle strip)

vertex VertexOut waveVertex(
    uint vertexID [[vertex_id]],
    constant float2* positions [[buffer(0)]]
) {
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    // Convert NDC (-1..1) to UV (0..1), flip Y so top-left is (0,0)
    out.uv = positions[vertexID] * 0.5 + 0.5;
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

// MARK: - Noise helpers

static float hash21(float2 p) {
    p = fract(p * float2(127.1, 311.7));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

static float smoothNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i),               hash21(i + float2(1, 0)), u.x),
        mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x),
        u.y
    );
}

// 3-octave FBM for organic shimmer
static float fbm3(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) {
        v += a * smoothNoise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

// MARK: - Signed Distance Function: Rounded Rectangle

/// Returns signed distance from `p` (in pixels, origin at center) to the
/// border of a rounded rectangle with half-size `b` and corner radius `r`.
/// Negative inside, positive outside.
static float sdRoundedRect(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// MARK: - Fragment shader

fragment float4 waveFragment(
    VertexOut in [[stage_in]],
    constant WaveUniforms& u [[buffer(0)]]
) {
    float2 uv  = in.uv;
    float  t   = u.time;
    float  amp = clamp(u.amplitude, 0.1, 1.0);

    // Pixel coordinates centered on screen
    float2 res = float2(u.resW, u.resH);
    float2 px  = (uv - 0.5) * res;   // centered pixel coords

    // Rounded rectangle SDF
    float2 halfSize = res * 0.5;
    float  cr       = u.cornerR;      // corner radius in pixels
    float  d        = sdRoundedRect(px, halfSize, cr);

    // Distance from the inner edge of the rounded rect (negative = inside)
    // We want glow to appear at d ≈ 0 (the border) and fade inward
    float edgeDist = -d;  // positive when inside the rect

    // ── Amplitude-reactive glow widths ──
    float breathe   = sin(t * 2.5) * 0.06 * amp;
    float ampScale  = 0.5 + amp * 0.5 + breathe;

    // Three glow layers (widths in pixels)
    float innerW = (3.0  + amp * 3.0) * ampScale;    // sharp crisp edge
    float midW   = (12.0 + amp * 10.0) * ampScale;   // medium glow
    float outerW = (30.0 + amp * 25.0) * ampScale;   // wide soft halo

    // Gaussian falloffs from edge
    float innerGlow = exp(-(edgeDist * edgeDist) / (innerW * innerW * 0.5));
    float midGlow   = exp(-(edgeDist * edgeDist) / (midW * midW * 0.5));
    float outerGlow = exp(-(edgeDist * edgeDist) / (outerW * outerW * 0.5));

    // Combine layers with decreasing intensity
    float glowMask = innerGlow * 1.0 + midGlow * 0.5 + outerGlow * 0.2;

    // Only render near the edge — fully transparent in center and outside
    // Kill fragments far from edge for performance
    if (edgeDist > outerW * 2.5 || edgeDist < -outerW * 1.5) {
        return float4(0.0);
    }

    // ── Angular gradient (Apple Intelligence palette) ──
    float angle = atan2(px.y, px.x);                     // -π..π
    float normAngle = (angle / (2.0 * M_PI_F)) + 0.5;   // 0..1

    // Rotate slowly + add noise-based perturbation
    float rotation = t * 0.15;
    float noiseOffset = (fbm3(float2(normAngle * 3.0 + t * 0.2, t * 0.1)) - 0.5) * 0.15;
    float gradPos = fract(normAngle + rotation + noiseOffset);

    // 7-color Apple Intelligence palette with smooth cycling
    const float3 palette[7] = {
        float3(0.737, 0.510, 0.953),   // #BC82F3 purple
        float3(0.961, 0.725, 0.918),   // #F5B9EA pink
        float3(0.553, 0.624, 1.000),   // #8D9FFF light blue
        float3(0.667, 0.431, 0.933),   // #AA6EEE violet
        float3(1.000, 0.404, 0.471),   // #FF6778 coral
        float3(1.000, 0.729, 0.443),   // #FFBA71 orange
        float3(0.776, 0.525, 1.000)    // #C686FF lavender
    };

    // Smooth color interpolation along the angular gradient
    float idx = gradPos * 7.0;
    int i0 = int(idx) % 7;
    int i1 = (i0 + 1) % 7;
    float frac = fract(idx);
    // Smooth hermite interpolation for softer color transitions
    frac = frac * frac * (3.0 - 2.0 * frac);
    float3 gradColor = mix(palette[i0], palette[i1], frac);

    // Add subtle shimmer variation along the edge
    float shimmer = fbm3(float2(normAngle * 8.0 + t * 0.5, edgeDist * 0.05 + t * 0.3));
    gradColor *= 0.85 + shimmer * 0.3;

    // ── Compose final color ──
    float3 color = gradColor * glowMask;

    // Brightness scales with amplitude
    float brightness = 0.6 + amp * 0.8;
    color *= brightness;

    // Reinhard tone mapping
    color = color / (color + 1.0);

    // Gamma correction (sRGB)
    color = pow(max(color, 0.0), float3(1.0 / 2.2));

    // Alpha driven by glow intensity
    float alpha = clamp(glowMask * brightness * 1.5, 0.0, 1.0);

    return float4(color, alpha);
}
