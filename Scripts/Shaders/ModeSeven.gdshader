shader_type canvas_item;

uniform sampler2D trackTexture : filter_nearest, repeat_disable;
uniform sampler2D grassTexture : filter_nearest, repeat_enable;
uniform sampler2D pathOverlay  : hint_default_black, filter_nearest, repeat_disable; // bound SubViewport (e.g. 1024x1024)
uniform mat3 mapMatrix;

uniform float overlay_strength = 1.0; // 0..1, scales skid visibility

// --- NEW: time-of-day / global tint (same look as BackgroundEffects) ---
uniform vec4  mapTint           : source_color = vec4(1.0, 1.0, 1.0, 1.0); // tint color
uniform float mapTintStrength   : hint_range(0.0, 1.0) = 1.0;              // 0=no tint, 1=full
uniform bool  tintOutsideGrass  = true;                                     // false = tint only track area

void fragment()
{
    // Project map-space (Mode 7) UV through view matrix
    vec3 uvh = mapMatrix * vec3(UV - vec2(0.5), 1.0);
    if (uvh.z <= 0.0) {
        discard;
    }
    vec2 projectedUV = uvh.xy / uvh.z;

    // Inside = track UV region [0..1]^2, otherwise sample tiled grass
    bool inside = (projectedUV.x >= 0.0 && projectedUV.x <= 1.0 &&
                   projectedUV.y >= 0.0 && projectedUV.y <= 1.0);

    vec4 texColor;
    float tileScale = float(textureSize(trackTexture, 0).x) / float(textureSize(grassTexture, 0).x);

    if (!inside) {
        vec2 grassUV = fract(projectedUV * tileScale);
        texColor = texture(grassTexture, grassUV);
    } else {
        texColor = texture(trackTexture, projectedUV);
    }

    if (texColor.a == 0.0) {
        discard;
    }

    // Overlay (skid marks) sampled in the same projected space as the track
    if (inside) {
        vec4 overlay = texture(pathOverlay, projectedUV);
        float a = overlay.a * overlay_strength;
        if (a > 0.0) {
            texColor.rgb = mix(texColor.rgb, overlay.rgb, a);
        }
    }

    // --- Apply the same time-of-day tint as BackgroundEffects ---
    // Multiply-style tint (matches Sprite2D.modulate), blended by mapTintStrength.
    if (tintOutsideGrass || inside) {
        vec3 tinted = texColor.rgb * mapTint.rgb;
        texColor.rgb = mix(texColor.rgb, tinted, mapTintStrength);
    }

    COLOR = texColor;
}
