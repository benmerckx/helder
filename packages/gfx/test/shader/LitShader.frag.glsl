#version 300 es
precision highp float;
precision highp int;
struct LitVaryings {
	vec3 normal;
	vec4 clip;
	vec2 uv;
	float shade;
};
struct Material {
	vec4 tint;
	int steps;
};
float posterize(float x, int steps) {
	if (steps < 2) {
		return x;
	}
	return floor(x * float(steps)) / float(steps - 1);
}
vec4 fs(LitVaryings i, Material m) {
	float glow = 0.0;
	int t = 0;
	int t_2 = m.steps;
	while (t < t_2) {
		int k = t;
		t += 1;
		glow += 1.0 / float(k + 2);
	}
	vec3 color = m.tint.xyz * (0.1 + posterize(i.shade, m.steps));
	if (i.uv.x > 0.5) {
		color = color.zyx;
	} else if (i.uv.y < 0.25) {
		color = 1.0 - color;
	}
	float check = ((int(i.uv.x * 8.0) % 2) == 0) ? 1.0 : 0.5;
	return vec4(clamp((color * check) + (glow * 0.01), vec3(0.0), vec3(1.0)), m.tint.w);
}
layout(std140) uniform Material_block {
	vec4 tint;
	int steps;
} u_1;
in vec3 v_normal;
in vec2 v_uv;
in float v_shade;
out vec4 out_color;
void main() {
	out_color = fs(LitVaryings(v_normal, gl_FragCoord, v_uv, v_shade), Material(u_1.tint, u_1.steps));
}
