#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The ambient field, on the GPU.
//
// ⚠️ WRITTEN HERE RATHER THAN BOUGHT. MetalForge (€5/month) generates shaders
// like this from an editor, which is a fine way to explore — but the output is a
// .metal file, and a .metal file is a thing this project can own outright. No
// subscription, no third-party licence sitting under the one visual layer of a
// product being sold, and no dependency to re-check when their terms change.
//
// ⚠️ RESTRAINT IS THE BRIEF. This app tells people uncomfortable things about
// their machine; a light show works against that. Two slow domes of champagne
// over the navy, low amplitude, no hard edges — the same picture the SwiftUI
// version drew with blurred circles, but as one GPU pass instead of a stack of
// views that once resized the whole window.

static inline float2 hash2(float2 p) {
    p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453) * 2.0 - 1.0;
}

// Value-gradient noise. Cheap, and smooth enough that no band shows on navy.
static inline float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(hash2(i + float2(0, 0)), f - float2(0, 0)),
                   dot(hash2(i + float2(1, 0)), f - float2(1, 0)), u.x),
               mix(dot(hash2(i + float2(0, 1)), f - float2(0, 1)),
                   dot(hash2(i + float2(1, 1)), f - float2(1, 1)), u.x), u.y);
}

/// `time` is supplied by the caller and is zero when Reduce Motion is on, which
/// makes the effect a still gradient rather than a special case in the shader.
[[ stitchable ]] half4 aurora(float2 pos, half4 current, float2 size, float time) {
    float2 uv = pos / size;

    // The ground: the app's navy, deepened toward the bottom.
    //
    // ⚠️ THE FIRST PASS CAME OUT FLAT. A straight top-to-bottom mix of two
    // navies reads as one uniform slab at window size — the layered version it
    // replaced had more depth, because overlapping blurred circles darken the
    // corners for free. The diagonal below plus the vignette further down are
    // what put that back; without them the content panels stop separating from
    // the background.
    half3 deep = half3(0.031, 0.055, 0.125);
    half3 mid  = half3(0.098, 0.165, 0.337);
    // Diagonal rather than vertical: the light reads as coming from one place.
    float ramp = smoothstep(-0.15, 1.05, uv.y * 0.78 + uv.x * 0.22);
    half3 col  = mix(mid, deep, half(ramp));

    // Two champagne domes drifting on different periods, so the motion never
    // settles into an obvious loop.
    float2 a = float2(0.78 + 0.05 * sin(time * 0.11), -0.10 + 0.04 * cos(time * 0.07));
    float2 b = float2(0.12 + 0.04 * cos(time * 0.09), 0.85 + 0.05 * sin(time * 0.13));
    float da = 1.0 - smoothstep(0.0, 0.85, distance(uv, a));
    float db = 1.0 - smoothstep(0.0, 0.70, distance(uv, b));

    half3 champagne = half3(0.969, 0.843, 0.580);
    col += champagne * half(da * 0.085);
    col += champagne * half(db * 0.045);

    // A slow warp so the domes are not perfect circles.
    float n = noise(uv * 2.4 + float2(time * 0.03, time * 0.02));
    col += champagne * half(max(0.0, n) * 0.020);

    // ⚠️ A VIGNETTE, OR THE PANELS DO NOT SEPARATE. Content sits on a lighter
    // surface at 6% white; against a uniform field its edges disappear at the
    // corners of a large window.
    float2 c = uv - 0.5;
    float vig = 1.0 - smoothstep(0.34, 0.92, length(c * float2(1.05, 1.0)));
    col *= half(mix(0.72, 1.0, vig));

    // ⚠️ DITHER, OR NAVY BANDS. A gradient this dark over a large window shows
    // visible steps at 8 bits; a sub-LSB of noise breaks them up for free.
    float d = (fract(sin(dot(pos, float2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
    col += half3(half(d));

    return half4(col, current.a);
}
