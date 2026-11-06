#version 300 es
precision highp float;
precision highp int;
struct SlotVaryings {
	vec4 clip;
	vec2 uv;
};
struct SlotView {
	vec4 scale;
};
struct SlotSurface {
	vec2 uv;
};
vec4 plainColor(SlotSurface s, SlotView view) {
	return vec4(s.uv, view.scale.x, 1.0);
}
vec4 fs(SlotVaryings i, SlotView view) {
	vec4 c = plainColor(SlotSurface(i.uv), view);
	float sum = 0.0;
	sum += 1.0;
	return c * sum;
}
layout(std140) uniform SlotView_block {
	vec4 scale;
} u_0;
in vec2 v_uv;
uniform vec2 u_target;
out vec4 out_color;
void main() {
	out_color = fs(SlotVaryings(vec4(gl_FragCoord.x, u_target.x + u_target.y * gl_FragCoord.y, gl_FragCoord.zw), v_uv), SlotView(u_0.scale));
}
