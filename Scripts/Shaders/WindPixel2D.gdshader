shader_type particles;

// ---------------- knobs ----------------
uniform float speed_min    = 140.0;  // px/s (toward camera = -Y)
uniform float speed_max    = 260.0;  // px/s
uniform float horiz_spread = 80.0;   // px/s sideways drift
uniform float accel_y      = 320.0;  // px/s^2 “gravity” toward camera

// --------- tiny hash PRNGs (manual) ----------
float hash11(float x) {
    return fract(sin(x * 12.9898) * 43758.5453);
}
vec2 hash21(float x) {
    float a = sin((x + 0.123) * 12.9898);
    float b = sin((x + 78.233) * 78.233);
    return fract(vec2(a, b) * 43758.5453);
}

void start() {
    // unique-ish seed per particle; TIME mixed in so new bursts don't repeat patterns
    float seed = float(INDEX) + TIME * 31.0;

    vec2 r = hash21(seed);                         // [0..1], [0..1]
    float vy = -mix(speed_min, speed_max, r.x);    // downward toward “camera”
    float vx = (r.y - 0.5) * horiz_spread;         // left/right drift

    VELOCITY = vec3(vx, vy, 0.0);                  // <- vec3 in 4.x

    // Optional spawn jitter (comment in if desired)
    // vec2 j = (vec2(hash11(seed+5.0), hash11(seed+7.0)) - 0.5) * 2.0; // -1..1
    // TRANSFORM[2].xy += j * 2.0;   // small 2px jitter in 2D
}

void process() {
    // pull “toward camera” over life
    VELOCITY.y += accel_y * DELTA;

    // Optional soft alpha ramp for pixel-trail feel
    // float t = AGE / max(LIFETIME, 0.0001);
    // float fade = smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.75, 1.0, t));
    // COLOR.a *= fade;
}
