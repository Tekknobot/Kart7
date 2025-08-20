shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex      : source_color, repeat_enable;

// --- ON/OFF + strength ---
uniform bool  enable = false;
uniform float intensity = 0.020;      // refraction amount
uniform float opacity   = 0.85;       // how strongly recolor applies inside mask (0..1)
uniform float grade_strength = 1.0;   // extra multiplier for recolor (0..1+)

// --- Mask motion look ---
uniform float time_scale = 0.6;
uniform float noise_scale_1 = 5.0;
uniform float noise_scale_2 = 2.0;

// --- Smoky palette (used if no palette_tex) ---
uniform vec3  shadow_col   = vec3(0.055, 0.060, 0.070); // deep charcoal
uniform vec3  mid_col      = vec3(0.300, 0.305, 0.320); // ashy grey
uniform vec3  highlight_col= vec3(0.750, 0.720, 0.680); // warm smoke highlight

// --- Optional palette ramp (luminance -> color). If provided, set use_palette_tex=true ---
uniform sampler2D palette_tex : source_color;
uniform bool use_palette_tex = false;

// --- Optional tint that softly leans the smoke toward a hue (0 = off) ---
uniform vec3 tint_color = vec3(0.85, 0.84, 0.83);
uniform float tint_amount = 0.1;      // 0..1

float luma(vec3 c) {
    // Rec. 709 luminance
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 tri_palette(float x, vec3 a, vec3 b, vec3 c) {
    // Smoothly blend a -> b -> c across x in [0..1]
    float m = smoothstep(0.0, 0.5, x);
    float h = smoothstep(0.5, 1.0, x);
    vec3 ab = mix(a, b, m);
    vec3 bc = mix(b, c, h);
    // Crossfade the two mixes near mid
    float cross = smoothstep(0.25, 0.75, x);
    return mix(ab, bc, cross);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    float t  = TIME * time_scale;

    // animated distortion (subtle refraction like rising heat)
    vec2 wobble = (texture(noise_tex, uv * noise_scale_1 + vec2(t, 0.0)).rg - 0.5) * intensity;
    vec4 base   = texture(SCREEN_TEXTURE, uv + wobble);

    // soft, cloudy mask that defines the “gas” region
    float m = texture(noise_tex, uv * noise_scale_2 + vec2(0.0, t)).r;
    // little feather to avoid hard edges
    m = smoothstep(0.05, 0.95, m);

    // compute luminance from the refracted screen color
    float y = luma(base.rgb);

    // palette map: either gradient texture or tri-color blend
    vec3 target_rgb;
    if (use_palette_tex) {
        // sample 1D ramp across x (use v=0.5 row)
        target_rgb = texture(palette_tex, vec2(clamp(y, 0.0, 1.0), 0.5)).rgb;
    } else {
        target_rgb = tri_palette(y, shadow_col, mid_col, highlight_col);
    }

    // optional gentle tint to push toward a hue
    target_rgb = mix(target_rgb, tint_color, clamp(tint_amount, 0.0, 1.0));

    // blend strength inside mask
    float k = clamp(opacity * grade_strength, 0.0, 1.0);
    vec3 graded = mix(base.rgb, target_rgb, m * k);

    // draw only where mask is (like your previous gas overlay)
    float out_a = m * float(enable);

    COLOR = vec4(graded, out_a);
}
