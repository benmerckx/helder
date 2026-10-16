#version 300 es
struct BuiltinVertex {
	vec4 pos;
};
struct BuiltinVaryings {
	vec4 pos;
	float a;
	vec2 b;
};
BuiltinVaryings vs(BuiltinVertex v) {
	mat4 m = mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(v.pos.xyz, 1.0)) * mat4(vec4(0.5, 0.0, 0.0, 0.0), vec4(0.0, 0.5, 0.0, 0.0), vec4(0.0, 0.0, 0.5, 0.0), vec4(0.0, 0.0, 0.0, 0.5));
	vec4 t = (m * v.pos) + (m[3] * 0.0);
	float t_2 = v.pos.w;
	return BuiltinVaryings(t, t_2, v.pos.xy);
}
layout(location = 0) in vec4 in_pos;
out float v_a;
out vec2 v_b;
void main() {
	BuiltinVaryings r = vs(BuiltinVertex(in_pos));
	gl_Position = vec4(r.pos.xy, 2.0 * r.pos.z - r.pos.w, r.pos.w);
	v_a = r.a;
	v_b = r.b;
}
