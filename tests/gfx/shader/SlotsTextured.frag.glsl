#version 300 es
precision highp float;
precision highp int;
precision highp sampler2D;
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
vec4 color(SlotSurface s, sampler2D image) {
	return texture(image, s.uv);
}
vec4 fs(SlotVaryings i, SlotView view, sampler2D image) {
	vec4 c = color(SlotSurface(i.uv), image);
	float sum = 0.0;
	sum += 1.0;
	return c * sum;
}
layout(std140) uniform SlotView_block {
	vec4 scale;
} u_0;
uniform sampler2D tex_1;
in vec2 v_uv;
uniform vec2 u_target;
out vec4 out_color;
void main() {
	out_color = fs(SlotVaryings(vec4(gl_FragCoord.x, u_target.x + u_target.y * gl_FragCoord.y, gl_FragCoord.zw), v_uv), SlotView(u_0.scale), tex_1);
}
