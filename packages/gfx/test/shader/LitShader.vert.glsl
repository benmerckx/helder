#version 300 es
struct LitVertex {
	vec3 pos;
	vec3 normal;
	vec2 uv;
};
struct Camera {
	mat4 viewProj;
	vec3 eye;
	float time;
};
struct LitVaryings {
	vec3 normal;
	vec4 clip;
	vec2 uv;
	float shade;
};
float lambert(vec3 n, vec3 l) {
	return max(dot(normalize(n), normalize(l)), 0.0);
}
LitVaryings vs(LitVertex v, Camera cam) {
	vec4 clip = cam.viewProj * vec4(v.pos, 1.0);
	float wobble = sin(cam.time + (v.pos.x * 3.0)) * 0.05;
	vec3 t = v.normal;
	vec4 t_2 = clip + vec4(wobble, 0.0, 0.0, 0.0);
	vec2 t_3 = v.uv.yx;
	return LitVaryings(t, t_2, t_3, lambert(v.normal, cam.eye - v.pos));
}
layout(std140) uniform Camera_block {
	mat4 viewProj;
	vec3 eye;
	float time;
} u_0;
layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec3 in_normal;
layout(location = 2) in vec2 in_uv;
out vec3 v_normal;
out vec2 v_uv;
out float v_shade;
void main() {
	LitVaryings r = vs(LitVertex(in_pos, in_normal, in_uv), Camera(u_0.viewProj, u_0.eye, u_0.time));
	gl_Position = r.clip;
	v_normal = r.normal;
	v_uv = r.uv;
	v_shade = r.shade;
}
