shader_type canvas_item;

uniform float src_hue    : hint_range(0.0, 1.0) = 0.33;   // ~120° (green)
uniform float hue_tol    : hint_range(0.0, 0.5) = 0.12;   // hue bandwidth around src_hue
uniform float sat_min    : hint_range(0.0, 1.0) = 0.25;   // ignore greys
uniform float val_min    : hint_range(0.0, 1.0) = 0.12;   // ignore deep shadows

uniform vec4  target_color : source_color = vec4(0.60, 1.00, 0.60, 1.0);
uniform float edge_soft  : hint_range(0.0, 1.0) = 0.20;   // soft edge
uniform float sat_boost  : hint_range(0.0, 2.0) = 1.00;   // push S a bit
uniform float val_mix    : hint_range(0.0, 1.0) = 0.50;   // 0=use orig V, 1=use target V

// --- helpers: RGB<->HSV ---
vec3 rgb2hsv(vec3 c){
    vec4 K = vec4(0., -1./3., 2./3., -1.);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.*d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c){
    vec3 p = abs(fract(c.x + vec3(0., 1./3., 2./3.)) * 6. - 3.);
    vec3 a = clamp(p - 1., 0., 1.);
    return c.z * mix(vec3(1.), a, c.y);
}
float hue_dist(float a, float b){
    float d = abs(a - b);
    return min(d, 1.0 - d);
}

void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    // Build mask for pixels we want to recolor (in HSV space)
    vec3 hsv = rgb2hsv(tex.rgb);
    float dh = hue_dist(hsv.x, src_hue);
    float within = smoothstep(hue_tol + edge_soft, hue_tol, dh);
    within *= step(sat_min, hsv.y) * step(val_min, hsv.z);

    // Target hue, keep original shading
    vec3 tgt_hsv = rgb2hsv(target_color.rgb);
    float out_v = mix(hsv.z, tgt_hsv.z, val_mix);
    float out_s = clamp(hsv.y * sat_boost, 0.0, 1.0);
    vec3 swapped = hsv2rgb(vec3(tgt_hsv.x, out_s, out_v));

    // Softly blend into the replaced hue; no early returns
    vec3 out_rgb = mix(tex.rgb, swapped, within);
    COLOR = vec4(out_rgb, tex.a);
}
