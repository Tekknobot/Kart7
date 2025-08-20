shader_type canvas_item;

uniform sampler2D trackTexture : filter_nearest;
uniform sampler2D grassTexture : filter_nearest;
uniform sampler2D pathOverlay;              // <-- bound SubViewport (1024x1024)
uniform mat3 mapMatrix;

void fragment()
{
    vec3 uv = mapMatrix * vec3(UV - vec2(0.5), 1.0);
    if (uv.z < 0.0) discard;

    vec2 projectedUV = uv.xy / uv.z;

    vec4 texColor;
    float tileScale = float(textureSize(trackTexture, 0).x) / float(textureSize(grassTexture, 0).x);

    if (projectedUV.x < 0.0 || projectedUV.x > 1.0 || projectedUV.y < 0.0 || projectedUV.y > 1.0) {
        vec2 grassUV = fract(projectedUV * tileScale);
        texColor = texture(grassTexture, grassUV);
    } else {
        texColor = texture(trackTexture, projectedUV);
    }

    if (texColor.a == 0.0) discard;

    // Sample the overlay in the SAME space as the track
    vec4 overlay = texture(pathOverlay, projectedUV);

    // Blend on top (only if overlay alpha > 0)
    texColor = mix(texColor, overlay, overlay.a);

    COLOR = texColor;
}
