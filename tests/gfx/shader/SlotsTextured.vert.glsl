#version 300 es
struct SlotVertex {
	vec2 pos;
};
struct SlotView {
	vec4 scale;
};
struct SlotVaryings {
	vec4 clip;
	vec2 uv;
};
SlotVaryings vs(SlotVertex v, SlotView view) {
	vec2 at = v.pos * view.scale.xy;
	return SlotVaryings(vec4(at, 0.0, 1.0), v.pos);
}
layout(std140) uniform SlotView_block {
	vec4 scale;
} u_0;
layout(location = 0) in vec2 in_pos;
out vec2 v_uv;
uniform vec2 u_target;
void main() {
	SlotVaryings r = vs(SlotVertex(in_pos), SlotView(u_0.scale));
	gl_Position = vec4(r.clip.x, -u_target.y * r.clip.y, 2.0 * r.clip.z - r.clip.w, r.clip.w);
	v_uv = r.uv;
}
