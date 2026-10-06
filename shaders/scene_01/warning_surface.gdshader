shader_type spatial;

instance uniform vec2 tile_repeat = vec2(1.0, 1.0);
uniform vec4 yellow_color : source_color = vec4(0.94, 0.72, 0.08, 1.0);
uniform vec4 dark_color : source_color = vec4(0.10, 0.09, 0.08, 1.0);
uniform float stripe_bands_per_cell : hint_range(2.0, 8.0, 0.5) = 5.0;
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.72;
uniform float metallic_value : hint_range(0.0, 1.0, 0.01) = 0.01;
uniform float specular_value : hint_range(0.0, 1.0, 0.01) = 0.30;

void fragment() {
    vec2 tiled_uv = UV * tile_repeat;
    float diagonal = tiled_uv.x + tiled_uv.y;
    float band_phase = fract(diagonal * stripe_bands_per_cell * 0.5);
    float use_yellow = step(0.5, band_phase);
    ALBEDO = mix(dark_color.rgb, yellow_color.rgb, use_yellow);
    ROUGHNESS = roughness_value;
    METALLIC = metallic_value;
    SPECULAR = specular_value;
}
