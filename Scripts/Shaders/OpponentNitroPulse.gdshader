shader_type canvas_item;

// === Recolor controls (green → target_color) ===
uniform float src_hue  : hint_range(0.0, 1.0) = 0.33;
uniform float hue_tol  : hint_range(0.0, 0.5) = 0.12;
uniform float edge_soft : hint_range(0.0, 1.0) = 0.20;

uniform float white_sat_max  : hint_range(0.0, 1.0) = 0.18;
uniform float white_sat_soft : hint_range(0.0, 0.5) = 0.08;
uniform float black_val_max  : hint_range(0.0, 1.0) = 0.18;
uniform float black_val_soft : hint_range(0.0, 0.5) = 0.10;
uniform float chroma_min     : hint_range(0.0, 1.0) = 0.06;
uniform float chroma_soft    : hint_range(0.0, 0.5) = 0.06;

uniform float sat_min : hint_range(0.0, 1.0) = 0.28;
uniform float val_min : hint_range(0.0, 1.0) = 0.14;

uniform vec4  target_color : source_color = vec4(0.60, 1.00, 0.60, 1.0);
uniform float sat_boost    : hint_range(0.0, 2.0) = 1.00;
uniform float val_mix      : hint_range(0.0, 1.0) = 0.50;

// === Nitro pulse controls ===
uniform float intensity : hint_range(0.0, 1.0) = 0.4;
uniform vec4  glow_color : source_color = vec4(0.55, 0.9, 1.0, 1.0);
uniform float chroma_px  : hint_range(0.0, 6.0) = 0.0;
uniform float outline_px : hint_range(0.0, 6.0) = 2.0;
uniform float wave_speed = 64.0;
uniform vec2  dir2       = vec2(1.0, 0.0);

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
	if (tex.a <= 0.001) {
		COLOR = vec4(0.0);
	}
	vec3 rgb = tex.rgb;
	vec3 hsv = rgb2hsv(rgb);

	// --- recolor mask ---
	float dh = hue_dist(hsv.x, src_hue);
	float hue_mask = smoothstep(hue_tol + edge_soft, hue_tol, dh);
	float not_white = smoothstep(white_sat_max, white_sat_max + white_sat_soft, hsv.y);
	float not_black = smoothstep(black_val_max, black_val_max + black_val_soft, hsv.z);
	float mx = max(rgb.r, max(rgb.g, rgb.b));
	float mn = min(rgb.r, min(rgb.g, rgb.b));
	float chroma = mx - mn;
	float not_grey = smoothstep(chroma_min, chroma_min + chroma_soft, chroma);
	float paint_gates = step(sat_min, hsv.y) * step(val_min, hsv.z);

	float within = hue_mask * not_white * not_black * not_grey * paint_gates;

	// recolor
	vec3 tgt_hsv = rgb2hsv(target_color.rgb);
	float out_v = mix(hsv.z, tgt_hsv.z, val_mix);
	float out_s = clamp(hsv.y * sat_boost, 0.0, 1.0);
	vec3 swapped = hsv2rgb(vec3(tgt_hsv.x, out_s, out_v));
	vec3 out_rgb = mix(rgb, swapped, within);

	// --- Nitro pulse (applied additively if intensity > 0) ---
	if (intensity > 0.001) {
		// normalize forward dir
		vec2 vdir = dir2;
		float dlen = length(vdir);
		if (dlen < 1e-5) { vdir = vec2(1.0, 0.0); dlen = 1.0; }
		vdir /= dlen;

		// chromatic shift
		vec2 px = TEXTURE_PIXEL_SIZE;
		vec2 shift = vdir * px * chroma_px * intensity;
		float r = texture(TEXTURE, UV + shift).r;
		float g = out_rgb.g;
		float b = texture(TEXTURE, UV - shift).b;
		vec3 chroma_col = vec3(r, g, b);

		// rim
		float radius = outline_px * intensity;
		vec2 o = px * radius;
		float a0 = tex.a;
		float aMax = max(max(max(
			texture(TEXTURE, UV + vec2(0.0, -o.y)).a,
			texture(TEXTURE, UV + vec2(0.0,  o.y)).a),
			max(texture(TEXTURE, UV + vec2( o.x, 0.0)).a,
				texture(TEXTURE, UV + vec2(-o.x, 0.0)).a)),
			max(max(texture(TEXTURE, UV + vec2( o.x, -o.y)).a,
					texture(TEXTURE, UV + vec2(-o.x, -o.y)).a),
				max(texture(TEXTURE, UV + vec2( o.x,  o.y)).a,
					texture(TEXTURE, UV + vec2(-o.x,  o.y)).a)));
		float rim = max(aMax - a0, 0.0) * intensity;

		// wave
		float wave = sin(dot(UV, vdir) * 80.0 - TIME * wave_speed);
		wave = smoothstep(0.3, 1.0, wave) * intensity;

		// combine
		vec3 glow = glow_color.rgb * (rim * 0.9 + wave * 0.25);
		out_rgb = mix(out_rgb, chroma_col, 0.55 * intensity) + glow;
	}

	COLOR = vec4(out_rgb, tex.a);
}
