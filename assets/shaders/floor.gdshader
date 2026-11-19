shader_type spatial;
render_mode diffuse_burley;

uniform vec3 wood_a : source_color = vec3(0.24, 0.18, 0.115);
uniform vec3 wood_b : source_color = vec3(0.1, 0.078, 0.055);

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
	float row = floor(wpos.z / 0.9);
	float f = fract(wpos.z / 0.9);
	float seam = smoothstep(0.0, 0.045, f) * smoothstep(0.0, 0.045, 1.0 - f);
	float grain = vnoise(vec3(wpos.x * 0.7, 0.0, wpos.z * 8.0));
	vec3 col = mix(wood_a, wood_b, hash13(vec3(row, 3.0, 1.0)));
	col *= 0.72 + 0.28 * grain;
	col *= 0.5 + 0.5 * seam;
	float wet = smoothstep(0.58, 0.85, vnoise(wpos * 0.55));
	col *= 1.0 - wet * 0.26;
	ALBEDO = col;
	ROUGHNESS = 0.86;
	SPECULAR = 0.28;
}
