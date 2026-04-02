//
//  SiriWaveShader.metal
//  AIFinanceManager
//
//  Aurora-style fragment shader — 5 color bands driven by FBM noise,
//  reacts to microphone amplitude. Matches Apple Intelligence Siri aesthetic.
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
    float2 u = f * f * (3.0 - 2.0 * f); // smoothstep
    return mix(
        mix(hash21(i),               hash21(i + float2(1, 0)), u.x),
        mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x),
        u.y
    );
}

// 4-octave fractional Brownian motion — produces organic, cloud-like turbulence
static float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value     += amplitude * smoothNoise(p);
        p         *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// MARK: - Fragment shader

fragment float4 waveFragment(
    VertexOut in [[stage_in]],
    constant WaveUniforms& u [[buffer(0)]]
) {
    float2 uv  = in.uv;
    float  t   = u.time;
    float  amp = clamp(u.amplitude, 0.15, 1.0); // never fully silent

    // Apple Intelligence color palette (violet → blue → teal → mint → pink)
    const float3 palette[5] = {
        float3(0.42, 0.15, 1.00),   // violet
        float3(0.10, 0.55, 1.00),   // blue
        float3(0.00, 0.82, 0.88),   // teal
        float3(0.18, 0.92, 0.50),   // mint-green
        float3(1.00, 0.22, 0.68)    // pink
    };

    float3 color = float3(0.0);

    // Vertical centers for each band — evenly spread across 30%–70% of height
    // so bands are visually distinct and don't wash out to white
    const float bandCenters[5] = { 0.30, 0.40, 0.50, 0.60, 0.70 };

    // Fade edges so waves don't clip hard at screen borders
    float edgeFade = smoothstep(0.0, 0.07, uv.x) * smoothstep(1.0, 0.93, uv.x);

    for (int i = 0; i < 5; i++) {
        float fi     = float(i) / 5.0;
        float speed  = 0.65 + fi * 0.55;   // each band moves at a different speed
        float freq   = 3.2  + fi * 1.1;    // each band has a different spatial frequency
        float phase  = fi   * 1.2566;      // 2π/5 — evenly spaced starting phases
        float center = bandCenters[i];

        // Primary sinusoidal wave — amplitude scaled so bands can cross each other
        float wave = sin(uv.x * freq * 6.2832 + t * speed + phase) * 0.07 * amp;

        // Organic FBM turbulence
        float2 noiseCoord = float2(uv.x * 2.2 + t * 0.18 + fi * 4.7,
                                   t * 0.13 + fi * 1.3);
        float noise = (fbm(noiseCoord) - 0.5) * 0.06 * amp;

        // Fine shimmer
        float ripple = sin(uv.x * freq * 20.0 + t * speed * 2.8 + phase * 1.7)
                       * 0.008 * amp;

        float waveY = center + wave + noise + ripple;

        // Narrow inverse-square glow — thin lines stay visually distinct
        float dist = abs(uv.y - waveY);
        float lw   = 0.0012 + amp * 0.0008;
        float glow = lw / (dist * dist + lw * 0.5);

        color += palette[i] * glow * edgeFade;
    }

    // Very faint background gradient bloom for depth
    float  cd    = abs(uv.y - 0.5);
    float3 bloom = mix(palette[1], palette[3], uv.x)
                   * (0.0008 / (cd * cd + 0.02))
                   * amp * 0.2;
    color += bloom;

    // Reinhard tone mapping — prevents over-bright artifacts from additive blending
    color = color / (color + 1.0);

    // Gamma correction (sRGB)
    color = pow(max(color, 0.0), float3(1.0 / 2.2));

    // Alpha driven by perceived brightness so the dark background stays transparent
    float alpha = clamp(dot(color, float3(0.299, 0.587, 0.114)) * 3.0, 0.0, 1.0);

    return float4(color, alpha);
}
