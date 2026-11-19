shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform sampler2D ghost_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(0.72, 0.95, 0.86);
uniform float intensity = 1.0;
uniform float dissolve = 0.0;

varying vec2 ghost_uv;

void vertex() {
	ghost_uv = UV;
	VERTEX.x += sin(TIME * 1.1 + UV.y * 5.0) * 0.055 * UV.y;
	VERTEX.z += sin(TIME * 0.7 + UV.y * 3.0) * 0.035;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
}

void fragment() {
	vec4 t = texture(ghost_tex, ghost_uv);
	float lum = max(t.r, max(t.g, t.b));
	float a = smoothstep(0.015, 0.26, lum) * t.a;
	float scan = 0.84 + 0.16 * sin(ghost_uv.y * 90.0 + TIME * 6.0);
	float flick = 0.84 + 0.16 * sin(TIME * 13.0);
	float alpha = clamp(a * scan * flick * (1.0 - dissolve), 0.0, 0.97);
	float rim = smoothstep(0.01, 0.07, lum) * (1.0 - smoothstep(0.07, 0.22, lum));
	vec3 col = (t.rgb * 3.4 + vec3(0.02, 0.05, 0.04)) * tint
		* (0.9 + 0.35 * intensity) * scan;
	col += tint * rim * 0.55 * intensity;
	ALBEDO = col;
	ALPHA = alpha;
	EMISSION = t.rgb * tint * 0.12 * intensity;
}
