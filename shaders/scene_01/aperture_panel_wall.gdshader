shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Aperture 风格白板墙：1.15 m 模数、4 cm 凹槽、2 cm 倒角、极轻微板间色差。
// 使用模型空间坐标做网格；面板方向由法线决定，因此同一材质可用于任意朝向的墙体，
// 也可用于把整段墙体合并后的静态网格。

uniform vec3 panel_color : source_color = vec3(0.910, 0.910, 0.894);
uniform vec3 seam_color : source_color = vec3(0.075, 0.082, 0.090);
uniform vec2 panel_size = vec2(1.15, 1.15);
uniform float seam_width : hint_range(0.0, 0.08, 0.005) = 0.024;
uniform float bevel_width : hint_range(0.0, 0.10, 0.005) = 0.045;
uniform float tone_jitter : hint_range(0.0, 0.08, 0.005) = 0.028;
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float metallic_value : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float specular_value : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float grime_amount : hint_range(0.0, 0.2, 0.01) = 0.05;
uniform float wall_height = 3.2;

varying vec2 v_grid;
varying float v_height;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	// Vertical walls: pick the horizontal axis that runs along the wall surface.
	if (abs(NORMAL.x) > abs(NORMAL.z)) {
		v_grid = vec2(VERTEX.z, VERTEX.y);
	} else {
		v_grid = vec2(VERTEX.x, VERTEX.y);
	}
	v_height = VERTEX.y;
}

void fragment() {
	vec2 uv = v_grid / panel_size;
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	vec2 dist = min(f, 1.0 - f) * panel_size;
	float seam_distance = min(dist.x, dist.y);

	float seam = 1.0 - smoothstep(seam_width, seam_width + 0.006, seam_distance);
	float bevel = 1.0 - smoothstep(seam_width, seam_width + bevel_width, seam_distance);

	float tone = mix(1.0 - tone_jitter, 1.0 + tone_jitter, hash21(cell));
	float bottom_grime = smoothstep(0.0, 0.5, 0.5 - v_height / wall_height) * grime_amount;
	vec3 albedo = panel_color * tone * (1.0 - bottom_grime);
	albedo *= 1.0 - 0.16 * bevel * (1.0 - seam);

	ALBEDO = mix(albedo, seam_color, seam);
	ROUGHNESS = mix(roughness_value, 0.82, seam * 0.5);
	METALLIC = metallic_value;
	SPECULAR = mix(specular_value, 0.15, seam);
}
