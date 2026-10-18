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
uniform float seam_width : hint_range(0.0, 0.10, 0.005) = 0.018;
uniform float seam_darkness : hint_range(0.0, 0.8, 0.01) = 0.34;
uniform float tile_tone_jitter : hint_range(0.0, 0.06, 0.005) = 0.018;

varying vec3 v_local;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 tiled_uv = UV * tile_repeat;
	vec4 sampled = texture(albedo_texture, tiled_uv) * tint;
	vec3 contrasted = (sampled.rgb - vec3(0.5)) * albedo_contrast + vec3(0.5);
	vec3 lifted = mix(contrasted, vec3(1.0), albedo_lift);
	float luma = dot(sampled.rgb, vec3(0.2126, 0.7152, 0.0722));

	// Geometry-aligned 1 m panel seams: independent of the authored raster tile,
	// so the playable grid reads crisply at every camera angle.
	vec2 cell_uv = v_local.xz;
	vec2 cell = floor(cell_uv);
	vec2 edge_distance = min(fract(cell_uv), 1.0 - fract(cell_uv));
	float seam = 1.0 - smoothstep(seam_width, seam_width + 0.012, min(edge_distance.x, edge_distance.y));
	float tone = mix(1.0 - tile_tone_jitter, 1.0 + tile_tone_jitter, hash21(cell));

	// Aperture porcelain: near-white warm-neutral tile with legible but thin seams.
	vec3 porcelain = vec3(0.76, 0.775, 0.735);
	vec3 normal_sample = texture(normal_texture, tiled_uv).rgb;
	float bevel_slope = clamp(length(normal_sample.rg * 2.0 - vec2(1.0)) * 0.65, 0.0, 1.0);
	float recessed_line = clamp((0.72 - luma) * 0.85, 0.0, 1.0);
	float ink_mask = 1.0 - smoothstep(0.62, 0.94, luma);
	vec3 ceramic = mix(porcelain, lifted, 0.12) * tone;
	ceramic *= 1.0 - 0.05 * recessed_line - 0.04 * bevel_slope - 0.18 * ink_mask;
	ceramic *= 1.0 - seam_darkness * seam;
	ALBEDO = ceramic;
	ROUGHNESS = clamp(roughness_value + (0.5 - luma) * roughness_variation + 0.12 * seam, 0.0, 1.0);
	METALLIC = metallic_value;
	SPECULAR = specular_value;
	NORMAL_MAP = texture(normal_texture, tiled_uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
}
