shader_type canvas_item;

uniform sampler2D trackTexture : filter_nearest;
uniform sampler2D grassTexture : filter_nearest;
uniform mat3 mapMatrix;

// overlay (optional)
uniform sampler2D pathOverlay : filter_nearest;
uniform float overlayAlpha = 1.0;

float safe_tex_w(sampler2D t) {
    ivec2 sz = textureSize(t, 0);
    return float(max(sz.x, 1)); // avoid 0
}

void fragment() {
    vec3 uvw = mapMatrix * vec3(UV - vec2(0.5), 1.0);
    if (uvw.z < 0.0) { discard; }
    vec2 projectedUV = uvw.xy / uvw.z;

    vec4 texColor;
    // Are both textures bound?
    bool has_track = (safe_tex_w(trackTexture) > 1.0);
    bool has_grass = (safe_tex_w(grassTexture) > 1.0);

    if (!has_track) {
        // Nothing bound -> show nothing instead of white
        discard;
    }

    if (projectedUV.x < 0.0 || projectedUV.x > 1.0 || projectedUV.y < 0.0 || projectedUV.y > 1.0) {
        if (has_grass) {
            float tileScale = safe_tex_w(trackTexture) / max(safe_tex_w(grassTexture), 1.0);
            vec2 grassUV = fract(projectedUV * tileScale);
            texColor = texture(grassTexture, grassUV);
        } else {
            // Fallback: if no grass set, just sample track with clamped UVs
            vec2 clampUV = clamp(projectedUV, 0.0, 1.0);
            texColor = texture(trackTexture, clampUV);
        }
    } else {
        texColor = texture(trackTexture, projectedUV);
    }

    if (texColor.a == 0.0) { discard; }

    // Overlay (optional)
    vec4 over = texture(pathOverlay, projectedUV);
    float a = clamp(over.a * overlayAlpha, 0.0, 1.0);
    vec3 rgb = mix(texColor.rgb, over.rgb, a);
    COLOR = vec4(rgb, texColor.a);
}
