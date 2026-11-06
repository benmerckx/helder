#version 300 es
struct SlotVertex {
	vec2 pos;
	vec4 tint;
	vec2 shift;
};
struct SlotView {
	vec4 scale;
};
struct SlotVaryings {
	vec4 clip;
	vec2 uv;
	vec4 tint;
};
SlotVaryings vs(SlotVertex v, SlotView view) {
	vec2 at = v.pos * view.scale.xy;
	at = at + v.shift;
	return SlotVaryings(vec4(at, 0.0, 1.0), v.pos, v.tint);
}
layout(std140) uniform SlotView_block {
	vec4 scale;
} u_0;
layout(location = 0) in vec2 in_pos;
layout(location = 1) in vec4 in_tint;
layout(location = 2) in vec2 in_shift;
out vec2 v_uv;
out vec4 v_tint;
uniform vec2 u_target;
void main() {
	SlotVaryings r = vs(SlotVertex(in_pos, in_tint, in_shift), SlotView(u_0.scale));
	gl_Position = vec4(r.clip.x, -u_target.y * r.clip.y, 2.0 * r.clip.z - r.clip.w, r.clip.w);
	v_uv = r.uv;
	v_tint = r.tint;
}
