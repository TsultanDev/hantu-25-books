shader_type canvas_item;

uniform float danger : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = UV;
	float d = distance(uv, vec2(0.5));
	float vig = smoothstep(0.34, 0.86, d);
	float edge = smoothstep(0.26, 0.62, d);
	float grain = hash(floor(uv * vec2(640.0, 360.0)) + floor(TIME * 24.0));
	float a = vig * 0.52 + edge * danger * 0.5 + grain * 0.045;
	vec3 col = mix(vec3(0.0), vec3(0.5, 0.02, 0.01), edge * danger);
	COLOR = vec4(col, clamp(a, 0.0, 0.93));
}
