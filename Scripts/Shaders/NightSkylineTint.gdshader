shader_type canvas_item;

/* Vertical midnight gradient: top (zenith) → bottom (horizon) */
uniform vec4  sky_top_color     : source_color = vec4(0.05, 0.08, 0.14, 1.0);
uniform vec4  sky_horizon_color : source_color = vec4(0.12, 0.16, 0.26, 1.0);

/* Shape/position */
uniform float gradient_curve : hint_range(0.1, 3.0) = 1.35;  // >1 darkens top more
uniform float horizon_offset : hint_range(-0.5, 0.5) = 0.0;  // slide gradient up/down

/* Near-white selection */
uniform float white_thr     : hint_range(0.0, 1.0) = 0.85;   // how white to qualify
uniform float white_softness: hint_range(0.0, 1.0) = 0.10;   // 0=hard edge, >0=softer
uniform bool  hard_threshold = false;                        // true = strict step()

/* Alpha handling */
uniform bool  use_texture_alpha = true;
uniform float fallback_alpha     : hint_range(0.0, 1.0) = 1.0;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    // Gradient factor (0 at top → 1 at bottom)
    float y = clamp(UV.y + horizon_offset, 0.0, 1.0);
    float f = pow(y, max(0.001, gradient_curve));
    vec3 grad = mix(sky_top_color.rgb, sky_horizon_color.rgb, f);

    // Near-white detector: bright & low saturation
    float maxc = max(max(tex.r, tex.g), tex.b);
    float minc = min(min(tex.r, tex.g), tex.b);
    float sat  = (maxc > 0.0) ? (maxc - minc) / maxc : 0.0;
    float lum  = dot(tex.rgb, vec3(0.2126, 0.7152, 0.0722));
    float white_like = lum * (1.0 - sat);

    // Mask for near-white pixels
    float t;
    if (hard_threshold) {
        t = step(white_thr, white_like); // strict: 0 or 1
    } else {
        t = smoothstep(white_thr - white_softness, white_thr + white_softness, white_like);
    }

    // Replace ONLY where near-white; keep everything else unchanged
    vec3 out_rgb = mix(tex.rgb, grad, t);
    float out_a = use_texture_alpha ? tex.a : fallback_alpha;
    COLOR = vec4(out_rgb, out_a);
}
