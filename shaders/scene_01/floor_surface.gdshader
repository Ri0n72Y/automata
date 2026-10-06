shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_linear, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear, repeat_enable;
instance uniform vec2 tile_repeat = vec2(1.0, 1.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform float albedo_lift : hint_range(0.0, 0.25, 0.01) = 0.0;
uniform float albedo_contrast : hint_range(0.5, 1.2, 0.01) = 1.0;
uniform float normal_depth : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.72;
uniform float roughness_variation : hint_range(0.0, 0.12, 0.005) = 0.0;
uniform float metallic_value : hint_range(0.0, 1.0, 0.01) = 0.02;
uniform float specular_value : hint_range(0.0, 1.0, 0.01) = 0.35;

void fragment() {
    vec2 tiled_uv = UV * tile_repeat;
    vec4 sampled = texture(albedo_texture, tiled_uv) * tint;
    vec3 contrasted = (sampled.rgb - vec3(0.5)) * albedo_contrast + vec3(0.5);
    vec3 lifted = mix(contrasted, vec3(1.0), albedo_lift);
    float luma = dot(sampled.rgb, vec3(0.2126, 0.7152, 0.0722));

    ALBEDO = lifted;
    ROUGHNESS = clamp(roughness_value + (0.5 - luma) * roughness_variation, 0.0, 1.0);
    METALLIC = metallic_value;
    SPECULAR = specular_value;
    NORMAL_MAP = texture(normal_texture, tiled_uv).rgb;
    NORMAL_MAP_DEPTH = normal_depth;
}
