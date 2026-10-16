#version 300 es
precision highp float;
precision highp int;
struct BuiltinVaryings {
	vec4 pos;
	float a;
	vec2 b;
};
vec4 fs(BuiltinVaryings i) {
	float x = i.a;
	vec2 v2 = i.b;
	vec3 v3 = vec3(v2, x);
	vec4 v4 = vec4(v3, 1.0);
	float s = ((((((((((abs(x) + sign(x)) + floor(x)) + ceil(x)) + fract(x)) + sqrt(x)) + inversesqrt(x + 1.0)) + sin(x)) + cos(x)) + tan(x)) + exp(x)) + log(x + 1.0);
	s += (((((min(x, 1.0) + max(x, 0.0)) + pow(x, 2.0)) + step(0.5, x)) + mix(0.0, 1.0, x)) + clamp(x, 0.0, 1.0)) + smoothstep(0.0, 1.0, x);
	s += ((((((sqrt(x) + abs(-x)) + min(x, 2.0)) + pow(2.0, x)) + floor(x)) + float(int(floor(x)))) + float(int(x * 3.0))) + 3.14159265358979312;
	vec3 w = ((((((((((abs(v3) + sign(v3)) + floor(v3)) + ceil(v3)) + fract(v3)) + sqrt(v3)) + inversesqrt(v3 + 1.0)) + sin(v3)) + cos(v3)) + tan(v3)) + exp(v3)) + log(v3 + 1.0);
	float lhs = 0.5;
	vec3 rhs = v3;
	w = w + (((((min(v3, v3.zyx) + max(v3, rhs * lhs)) + pow(v3, vec3(2.0))) + step(v3, vec3(0.5))) + mix(v3, -v3, vec3(0.5))) + mix(v3, v3.yzx, v3));
	w = w + ((((clamp(v3, vec3(0.0), vec3(1.0)) + clamp(v3, v3.yzx, v3.zxy)) + smoothstep(vec3(0.0), vec3(1.0), v3)) + smoothstep(vec3(0.0), vec3(1.0), v3)) + reflect(v3, normalize(v3.zyx)));
	w = w + ((((((cross(v3, v3.yzx) + vec3(dot(v3, v3), length(v3), distance(v3, v3.zyx))) + vec3(1.0, v2)) + vec3(v2.yx, 1.0)) + (v3 / 2.0)) - (1.0 / (v3 + 1.0))) - 1.0);
	int n = 0;
	int k = 7;
	while (n < 10) {
		n += 1;
		if (n == 3) {
			continue;
		}
		if ((n > 8) || (((k & 1) == 0) && (n != 5))) {
			break;
		}
		k = ((k << 1) | n) ^ (k >> 1);
	}
	float t = (x > 0.5) ? x : (-x);
	return ((((vec4(w, s) * 0.01) + (v4 * (float(n + (k % 5)) + t))) + vec4(v2, v2)) + vec4(x, v3)) - vec4(x);
}
in float v_a;
in vec2 v_b;
out vec4 out_color;
void main() {
	out_color = fs(BuiltinVaryings(gl_FragCoord, v_a, v_b));
}
