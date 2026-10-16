#version 300 es
struct Vertex {
	vec2 pos;
	vec3 color;
};
struct Varyings {
	vec4 pos;
	vec3 color;
};
Varyings vs(Vertex v) {
	return Varyings(vec4(v.pos, 0.0, 1.0), v.color);
}
layout(location = 0) in vec2 in_pos;
layout(location = 1) in vec3 in_color;
out vec3 v_color;
void main() {
	Varyings r = vs(Vertex(in_pos, in_color));
	gl_Position = vec4(r.pos.xy, 2.0 * r.pos.z - r.pos.w, r.pos.w);
	v_color = r.color;
}
