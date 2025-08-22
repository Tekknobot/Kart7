shader_type canvas_item;

// --- detect source green band ---
uniform float src_hue  : hint_range(0.0, 1.0) = 0.33;  // ~120°
uniform float hue_tol  : hint_range(0.0, 0.5) = 0.12;
uniform float edge_soft : hint_range(0.0, 1.0) = 0.20;

// --- HARD protection against whites / blacks (soft edges) ---
uniform float white_sat_max  : hint_range(0.0, 1.0) = 0.18;
uniform float white_sat_soft : hint_range(0.0, 0.5) = 0.08;

uniform float black_val_max  : hint_range(0.0, 1.0) = 0.18; // raised to protect dark rubber
uniform float black_val_soft : hint_range(0.0, 0.5) = 0.10;

// --- NEW: chroma gate (protect near-greys / low-contrast rubber) ---
uniform float chroma_min     : hint_range(0.0, 1.0) = 0.06; // max(rgb)-min(rgb)
uniform float chroma_soft    : hint_range(0.0, 0.5) = 0.06;

// --- softer paint gates ---
uniform float sat_min : hint_range(0.0, 1.0) = 0.28;  // a touch stricter
uniform float val_min : hint_range(0.0, 1.0) = 0.14;

// --- target color & shading preservation ---
uniform vec4  target_color : source_color = vec4(0.60, 1.00, 0.60, 1.0);
uniform float sat_boost    : hint_range(0.0, 2.0) = 1.00;
uniform float val_mix      : hint_range(0.0, 1.0) = 0.50;

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

void fragment(){
	vec4 tex = texture(TEXTURE, UV);
	vec3 rgb = tex.rgb;
	vec3 hsv = rgb2hsv(rgb);

	// hue proximity (green band)
	float dh = hue_dist(hsv.x, src_hue);
	float hue_mask = smoothstep(hue_tol + edge_soft, hue_tol, dh);

	// protect whites (low S) and blacks (low V) with soft ramps
	float not_white = smoothstep(white_sat_max, white_sat_max + white_sat_soft, hsv.y);
	float not_black = smoothstep(black_val_max, black_val_max + black_val_soft, hsv.z);

	// NEW: protect low-chroma (rubber/greys). Chroma = max(rgb) - min(rgb).
	float mx = max(rgb.r, max(rgb.g, rgb.b));
	float mn = min(rgb.r, min(rgb.g, rgb.b));
	float chroma = mx - mn;
	float not_grey = smoothstep(chroma_min, chroma_min + chroma_soft, chroma);

	// softer paint gates
	float paint_gates = step(sat_min, hsv.y) * step(val_min, hsv.z);

	// final mask — tires will fail not_black or not_grey (or both)
	float within = hue_mask * not_white * not_black * not_grey * paint_gates;

	// swap hue, keep shading
	vec3 tgt_hsv = rgb2hsv(target_color.rgb);
	float out_v = mix(hsv.z, tgt_hsv.z, val_mix);
	float out_s = clamp(hsv.y * sat_boost, 0.0, 1.0);
	vec3 swapped = hsv2rgb(vec3(tgt_hsv.x, out_s, out_v));

	vec3 out_rgb = mix(rgb, swapped, within);
	COLOR = vec4(out_rgb, tex.a);
}
