// FinishFlag.gdshader (Godot 4.4.1) — UV-warped ripples version
shader_type canvas_item;

// -------- Appearance (yours) --------
uniform vec4 light_color : source_color = vec4(1.00, 1.00, 1.00, 1.0);
uniform vec4 dark_color  : source_color = vec4(0.05, 0.05, 0.05, 1.0);
uniform vec2 tiles = vec2(12.0, 8.0);
uniform float angle_deg = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform float fade_soft : hint_range(0.0, 0.4) = 0.08;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

// -------- Wave controls (UV units, not pixels) --------
// amplitudes are in UV (1.0 = full rect height)
uniform float wave_amp_uv   : hint_range(0.0, 0.25) = 0.06;
uniform float wave_len_uv   : hint_range(0.05, 2.0) = 0.35;
uniform float wave_speed_hz : hint_range(-8.0, 8.0) = 2.2;

uniform float ripple_amp_uv   : hint_range(0.0, 0.10) = 0.015;
uniform float ripple_len_uv   : hint_range(0.05, 1.0) = 0.18;
uniform float ripple_speed_hz : hint_range(-12.0, 12.0) = 6.0;

// Pin to a “pole” on left
uniform float pin_left : hint_range(0.0, 1.0) = 0.85;
uniform float pin_width_uv : hint_range(0.0, 0.5) = 0.15;

// Fake lighting
uniform float light_strength : hint_range(0.0, 1.0) = 0.35; // 0 = off
uniform vec2  light_dir = vec2(0.35, -0.8);

vec2 rotate_uv(vec2 uv, float rad, vec2 pivot) {
    float s = sin(rad), c = cos(rad);
    vec2 p = uv - pivot;
    return vec2(p.x * c - p.y * s, p.x * s + p.y * c) + pivot;
}

float pin_falloff(float x_uv) {
    // 1 near left edge, 0 across the cloth
    return mix(1.0, 0.0, smoothstep(0.0, pin_width_uv, x_uv));
}

float wave_h(float x, float t) {
    float w1 = sin((x / max(1e-4, wave_len_uv)) * TAU - t * TAU * wave_speed_hz);
    float w2 = sin((x / max(1e-4, ripple_len_uv)) * TAU + t * TAU * ripple_speed_hz);
    return wave_amp_uv * w1 + ripple_amp_uv * w2; // height in UV units
}

// derivative wrt x for lighting (analytical)
float wave_h_dx(float x, float t) {
    float k1 = TAU / max(1e-4, wave_len_uv);
    float k2 = TAU / max(1e-4, ripple_len_uv);
    float d1 =  wave_amp_uv   * k1 * cos((x / max(1e-4, wave_len_uv)) * TAU - t * TAU * wave_speed_hz);
    float d2 =  ripple_amp_uv * k2 * cos((x / max(1e-4, ripple_len_uv)) * TAU + t * TAU * ripple_speed_hz);
    return d1 + d2;
}

void fragment() {
    // Rotate the cloth’s pattern space so checker sticks to it
    vec2 uv = rotate_uv(UV, radians(angle_deg), vec2(0.5));

    // Smooth ripples by *warping UV.y* with a height field (no vertex displacement)
    float pin = pin_left * pin_falloff(uv.x);
    float h   = wave_h(uv.x, TIME) * (1.0 - pin);
    uv.y += h;

    // Checker
    vec2 g   = uv * tiles;
    vec2 idx = floor(g);
    float parity = mod(idx.x + idx.y, 2.0);

    // Diagonal reveal
    float diag = (idx.x + idx.y + 0.5) / max(1.0, (tiles.x + tiles.y));
    float mask = smoothstep(fade - fade_soft, fade + fade_soft, diag);
    mask *= step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);

    // Base color
    vec4 col = mix(light_color, dark_color, parity);

    // Fake lighting from slope dh/dx
    vec2 L = normalize(light_dir);
    float slope = wave_h_dx(UV.x, TIME) * (1.0 - pin);   // use unrotated x for stability
    // Treat slope as a “tilt” toward/away from light.x
    float lambert = clamp(1.0 - slope * L.x, 0.0, 1.0);
    float shade = mix(1.0, mix(0.8, 1.25, lambert), light_strength);
    col.rgb *= shade;

    col.a *= opacity * mask;
    COLOR = col;
}
