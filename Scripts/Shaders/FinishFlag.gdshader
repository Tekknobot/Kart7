// FinishFlag.gdshader (Godot 4.4.1)
shader_type canvas_item;

// Checker colors
uniform vec4 light_color : source_color = vec4(1.00, 1.00, 1.00, 1.0);
uniform vec4 dark_color  : source_color = vec4(0.05, 0.05, 0.05, 1.0);

// Grid density (tiles across X and Y)
uniform vec2 tiles = vec2(12.0, 8.0);

// Rotate the grid (degrees)
uniform float angle_deg = 0.0;

// 0 → hidden, 1 → fully revealed (animate this)
uniform float fade : hint_range(0.0, 1.0) = 0.0;

// Soft edge of the diagonal reveal
uniform float fade_soft : hint_range(0.0, 0.4) = 0.08;

// Global opacity
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

vec2 rotate_uv(vec2 uv, float rad, vec2 pivot) {
    float s = sin(rad);
    float c = cos(rad);
    vec2 p = uv - pivot;
    vec2 r = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
    return r + pivot;
}

void fragment() {
    // Rotate checker space around the rect center
    vec2 uv = rotate_uv(UV, radians(angle_deg), vec2(0.5));

    // Tile index
    vec2 g   = uv * tiles;
    vec2 idx = floor(g);

    // Checker parity
    float parity = mod(idx.x + idx.y, 2.0);

    // Diagonal reveal metric normalized to [0..1]
    float diag = (idx.x + idx.y + 0.5) / max(1.0, (tiles.x + tiles.y));

    // Fade mask with soft edge
    float mask = smoothstep(fade - fade_soft, fade + fade_soft, diag);

    // Clip to the ColorRect (avoid rotated bleed)
    mask *= step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);

    vec4 col = mix(light_color, dark_color, parity);
    col.a *= opacity * mask;

    COLOR = col;
}
