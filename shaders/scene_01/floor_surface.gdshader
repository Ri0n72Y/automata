shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_linear, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear, repeat_enable;
instance uniform vec2 tile_repeat = vec2(1.0, 1.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform float normal_depth : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.72;
uniform float metallic_value : hint_range(0.0, 1.0, 0.01) = 0.02;
uniform float specular_value : hint_range(0.0, 1.0, 0.01) = 0.35;

void fragment() {
    vec2 tiled_uv = UV * tile_repeat;
    vec4 base = texture(albedo_texture, tiled_uv) * tint;
    ALBEDO = base.rgb;
    ROUGHNESS = roughness_value;
    METALLIC = metallic_value;
    SPECULAR = specular_value;
    NORMAL_MAP = texture(normal_texture, tiled_uv).rgb;
    NORMAL_MAP_DEPTH = normal_depth;
}
