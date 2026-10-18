shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Aperture 风格的青色 LED 点阵列（地面导引线与墙面竖向点线）。
// 平面使用局部坐标画等距圆点：长轴为点列方向，短轴为带宽。

uniform vec4 dot_color : source_color = vec4(0.247, 0.776, 0.808, 1.0);
uniform float dot_spacing = 0.5;
uniform float dot_radius = 0.055;
uniform float intensity = 2.6;
uniform float softness = 0.02;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float u = v_local.x;
	float w = v_local.z;
	float along = abs(u) >= abs(w) ? u : w;
	float across = abs(u) >= abs(w) ? w : u;
	float center = (floor(along / dot_spacing) + 0.5) * dot_spacing;
	float distance_to_dot = length(vec2(along - center, across));
	float mask = 1.0 - smoothstep(dot_radius, dot_radius + softness, distance_to_dot);
	if (mask < 0.01) {
		discard;
	}
	ALBEDO = dot_color.rgb * intensity;
	ALPHA = mask;
}
