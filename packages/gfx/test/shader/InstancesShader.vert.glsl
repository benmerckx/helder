#version 300 es
struct InstanceVertex {
	vec2 corner;
	vec2 at;
	float size;
	float angle;
	vec3 color;
};
struct InstanceField {
	vec2 scale;
	float time;
};
struct InstanceVaryings {
	vec4 pos;
	vec3 color;
	vec2 corner;
};
InstanceVaryings vs(InstanceVertex v, InstanceField f) {
	float a = v.angle + f.time;
	float c = cos(a);
	float s = sin(a);
	vec2 p = (vec2((v.corner.x * c) - (v.corner.y * s), (v.corner.x * s) + (v.corner.y * c)) * v.size) + v.at;
	return InstanceVaryings(vec4(p * f.scale, 0.0, 1.0), v.color, v.corner);
}
layout(std140) uniform InstanceField_block {
	vec2 scale;
	float time;
} u_0;
layout(location = 0) in vec2 in_corner;
layout(location = 1) in vec2 in_at;
layout(location = 2) in float in_size;
layout(location = 3) in float in_angle;
layout(location = 4) in vec3 in_color;
out vec3 v_color;
out vec2 v_corner;
uniform vec2 u_target;
void main() {
	InstanceVaryings r = vs(InstanceVertex(in_corner, in_at, in_size, in_angle, in_color), InstanceField(u_0.scale, u_0.time));
	gl_Position = vec4(r.pos.x, -u_target.y * r.pos.y, 2.0 * r.pos.z - r.pos.w, r.pos.w);
	v_color = r.color;
	v_corner = r.corner;
}
