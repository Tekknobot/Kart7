shader_type canvas_item;

// "Blackish" detection
uniform float dark_threshold : hint_range(0.0, 1.0) = 0.15;

// Flash timing for dark pixels
uniform float flash_speed = 60.0;
uniform float flash_duty  : hint_range(0.0, 1.0) = 0.25; // fraction of cycle ON

// White flash opacity (multiplied by source alpha)
uniform float white_alpha : hint_range(0.0, 1.0) = 1.0;

// Red tint for non-dark pixels
uniform vec3  red_color = vec3(1.0, 0.0, 0.0);
uniform float red_strength : hint_range(0.0, 1.0) = 0.6; // 0=no tint, 1=full red

void fragment() {
    // Raw texture only (doesn't use node Modulate)
    vec4 tex = texture(TEXTURE, UV);
    if (tex.a <= 0.001) {
        COLOR = vec4(0.0);
    }

    // Detect dark texels by luminance
    float luma = dot(tex.rgb, vec3(0.2126, 0.7152, 0.0722));
    bool is_dark = (luma <= dark_threshold);

    // Flash window (binary)
    float s = 0.5 + 0.5 * sin(TIME * flash_speed); // 0..1
    bool flash_on = (s >= 1.0 - flash_duty);

    vec4 outc = tex;

    if (is_dark) {
        // Dark area: flash to pure white during ON window, else original
        if (flash_on) {
            outc = vec4(vec3(1.0), tex.a * white_alpha);
        } else {
            outc = tex;
        }
    } else {
        // Non-dark area: apply red tint
        vec3 tinted = mix(tex.rgb, red_color, red_strength);
        outc = vec4(tinted, tex.a);
    }

    COLOR = outc;
}
