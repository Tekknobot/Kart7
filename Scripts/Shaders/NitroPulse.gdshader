shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;   // live: 0..1
uniform vec4  glow_color : source_color = vec4(0.55, 0.9, 1.0, 1.0);
uniform float chroma_px  : hint_range(0.0, 6.0) = 0.0;  // pixels of chromatic shift
uniform float outline_px : hint_range(0.0, 6.0) = 2.0;  // pixels for additive rim
uniform float wave_speed = 8.2;                         // scan/wave speed
uniform vec2  dir2       = vec2(1.0, 0.0);              // forward in screen-UV space

void fragment() {
    // Base sample
    vec4 base = texture(TEXTURE, UV);
    if (base.a <= 0.001) {
        COLOR = vec4(0.0);
    }

    // Normalize forward dir (fallback to X if near zero)
    vec2 vdir = dir2;
    float dlen = length(vdir);
    if (dlen < 1e-5) {
        vdir = vec2(1.0, 0.0);
        dlen = 1.0;
    }
    vdir /= dlen;

    // --- Chromatic aberration along forward direction ---
    vec2 px = TEXTURE_PIXEL_SIZE;
    vec2 shift = vdir * px * chroma_px * intensity;
    float r   = texture(TEXTURE, UV + shift).r;
    float g   = base.g;
    float b   = texture(TEXTURE, UV - shift).b;
    vec3 chroma_col = vec3(r, g, b);

    // --- Soft additive “rim” (inner glow) from alpha neighborhood ---
    float radius = outline_px * intensity;
    vec2 o = px * radius;

    float a0 = base.a;
    float aN = texture(TEXTURE, UV + vec2( 0.0, -o.y)).a;
    float aS = texture(TEXTURE, UV + vec2( 0.0,  o.y)).a;
    float aE = texture(TEXTURE, UV + vec2( o.x,  0.0)).a;
    float aW = texture(TEXTURE, UV + vec2(-o.x,  0.0)).a;
    float aNE= texture(TEXTURE, UV + vec2( o.x, -o.y)).a;
    float aNW= texture(TEXTURE, UV + vec2(-o.x, -o.y)).a;
    float aSE= texture(TEXTURE, UV + vec2( o.x,  o.y)).a;
    float aSW= texture(TEXTURE, UV + vec2(-o.x,  o.y)).a;

    float aMax = max(max(max(aN, aS), max(aE, aW)), max(max(aNE, aNW), max(aSE, aSW)));
    float rim = max(aMax - a0, 0.0);                   // edges brighten
    rim *= intensity;                                   // scale by live intensity

    // --- Subtle scan/wave along forward direction ---
    float wave = sin(dot(UV, vdir) * 80.0 - TIME * wave_speed);
    wave = smoothstep(0.3, 1.0, wave) * intensity;      // 0..1 pulse, gated by intensity

    // Compose:
    vec3 glow = glow_color.rgb * (rim * 0.9 + wave * 0.25);
    vec3 mixed = mix(base.rgb, chroma_col, 0.55 * intensity) + glow;

    COLOR = vec4(mixed, base.a);
}
