shader_type canvas_item;

/* Screen size for aspect; uses screen texture if available, else fallback */
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform vec2 viewport_size = vec2(1280.0, 720.0);

/* Camera-ish controls */
uniform float fov_y   = 1.0;   // smaller = zoom in
uniform float bank_rad = 0.0;  // radians; tilt tunnel (drive from steer)

/* Tunnel shape */
uniform float tunnel_radius = 0.85;  // 0..1
uniform float fog_strength  = 0.7;   // depth fade

/* Grid settings */
uniform float ring_freq     = 0.20;  // rings per unit depth
uniform float ang_bands     = 16.0;  // vertical grid bands around tube
uniform float line_thickness = 0.05; // 0..0.2 (soft edge SDF)
uniform float glow_boost    = 1.6;   // brightens line cores
uniform float scroll_speed  = 1.2;   // rings scroll toward camera
uniform vec4  line_color    = vec4(0.2, 0.9, 1.0, 1.0);   // neon
uniform vec4  bg_color      = vec4(0.00, 0.02, 0.06, 1.0); // dark

/* Composition */
uniform bool additive_blend = true;  // set CanvasItemMaterial Blend=Add for best look

/* --- helpers --- */
vec2 screen_size() {
    ivec2 isz = textureSize(SCREEN_TEXTURE, 0);
    if (isz.x > 0 && isz.y > 0) return vec2(isz);
    return max(viewport_size, vec2(1.0));
}

/* rotate 2D vector by angle 'a' (avoids mat2 ctor issues) */
vec2 rotate2(vec2 v, float a) {
    float c = cos(a);
    float s = sin(a);
    return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

void fragment() {
    // NDC in [-1,1], aspect-corrected
    vec2 ss = screen_size();
    float aspect = ss.x / max(ss.y, 1.0);
    vec2 ndc = UV * 2.0 - 1.0;
    ndc.x *= aspect;

    // Ray from camera through view plane (z = 1/fov_y)
    vec3 ro = vec3(0.0);
    vec3 rd = normalize(vec3(ndc, 1.0 / max(fov_y, 1e-4)));

    // Bank/tilt ray
    rd.xy = rotate2(rd.xy, bank_rad);

    // Ray–infinite cylinder (radius about Z axis)
    float a = dot(rd.xy, rd.xy);
    if (a <= 1e-6) { COLOR = bg_color; }
    float t = tunnel_radius / sqrt(a);

    // Point on cylinder
    vec3 p = ro + rd * t;

    // Param coords on tube
    float z = p.z + TIME * scroll_speed;             // animate rings
    float theta = atan(p.y, p.x);                    // -pi..pi
    float ang = (theta + 3.14159265) / (2.0 * 3.14159265); // 0..1 around

    // Grid SDFs (angle & depth)
    float gx = abs(fract(ang * max(ang_bands, 1.0)) - 0.5);
    float gz = abs(fract(z   * max(ring_freq, 0.0001)) - 0.5);

    float tx = smoothstep(line_thickness, 0.0, gx); // verticals
    float tz = smoothstep(line_thickness, 0.0, gz); // rings
    float grid = max(tx, tz);

    // Glow & fog
    float core = pow(grid, glow_boost);
    float fog  = exp(-fog_strength * t);

    vec3 col = bg_color.rgb * fog + line_color.rgb * core;
    float alpha = 1.0;

    if (additive_blend) {
        // works nicely with CanvasItemMaterial blend=Add
        COLOR = vec4(col * alpha, alpha);
    } else {
        COLOR = vec4(col, alpha);
    }
}
