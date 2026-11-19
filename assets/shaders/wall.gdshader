shader_type spatial;
render_mode diffuse_burley;

uniform vec3 color_a : source_color = vec3(0.34, 0.31, 0.25);
uniform vec3 color_b : source_color = vec3(0.13, 0.135, 0.12);
uniform vec3 moss : source_color = vec3(0.2, 0.27, 0.17);

varying vec3 wpos;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z
	);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = vnoise(wpos * 0.65) * 0.55
		+ vnoise(wpos * 2.3) * 0.3
		+ vnoise(wpos * 7.0) * 0.15;
	float streak = vnoise(vec3(wpos.x * 2.2, wpos.y * 0.2, wpos.z * 2.2));
	float damp = smoothstep(0.0, 2.0, wpos.y);
	vec3 col = mix(color_b, color_a, n);
	col = mix(col, moss, smoothstep(0.5, 0.95, streak) * 0.35 * (1.0 - damp));
	col *= 0.72 + 0.28 * damp;
	col *= 0.85 + 0.15 * n;
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}
