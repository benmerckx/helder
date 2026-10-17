#version 300 es
precision highp sampler2D;
struct TexVertex {
	vec2 pos;
	vec2 uv;
};
struct TexVaryings {
	vec4 pos;
	vec2 uv;
	float lift;
};
TexVaryings vs(TexVertex v, sampler2D height) {
	vec4 t = vec4(v.pos, 0.0, 1.0);
	vec2 t_2 = v.uv;
	return TexVaryings(t, t_2, textureLod(height, v.uv, 0.0).x);
}
uniform sampler2D tex_0;
layout(location = 0) in vec2 in_pos;
layout(location = 1) in vec2 in_uv;
out vec2 v_uv;
out float v_lift;
uniform vec2 u_target;
void main() {
	TexVaryings r = vs(TexVertex(in_pos, in_uv), tex_0);
	gl_Position = vec4(r.pos.x, -u_target.y * r.pos.y, 2.0 * r.pos.z - r.pos.w, r.pos.w);
	v_uv = r.uv;
	v_lift = r.lift;
}
