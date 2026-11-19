shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.72, 0.3, 1.0);
uniform float pulse = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
}

void fragment() {
	float d = length(UV - vec2(0.5));
	float a = pow(smoothstep(0.5, 0.0, d), 2.2);
	ALBEDO = glow_color.rgb * pulse;
	ALPHA = a * 0.7;
}
