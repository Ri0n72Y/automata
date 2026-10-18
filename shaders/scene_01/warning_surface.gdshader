shader_type spatial;

// Aperture 边界带：深灰防滑底板 + 极低对比的斜向踏纹，替代通用黄黑工业警示。
instance uniform vec2 tile_repeat = vec2(1.0, 1.0);
instance uniform vec2 tile_origin = vec2(0.0, 0.0);
uniform vec4 base_color : source_color = vec4(0.075, 0.082, 0.090, 1.0);
uniform vec4 tread_color : source_color = vec4(0.115, 0.125, 0.138, 1.0);
uniform float stripe_bands_per_cell : hint_range(2.0, 12.0, 0.5) = 8.0;
uniform float stripe_contrast : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.6;
uniform float metallic_value : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float specular_value : hint_range(0.0, 1.0, 0.01) = 0.35;

void fragment() {
    vec2 field_tile_uv = UV * tile_repeat + tile_origin;
    float diagonal = field_tile_uv.x + field_tile_uv.y;
    float band_index = floor(diagonal * stripe_bands_per_cell * 0.5);
    float tread = mod(band_index, 2.0) * stripe_contrast;
    ALBEDO = mix(base_color.rgb, tread_color.rgb, tread);
    ROUGHNESS = roughness_value;
    METALLIC = metallic_value;
    SPECULAR = specular_value;
}
