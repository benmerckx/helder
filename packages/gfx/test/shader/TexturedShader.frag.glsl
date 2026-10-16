#version 300 es
precision highp float;
precision highp int;
precision highp sampler2D;
struct TexVaryings {
	vec4 pos;
	vec2 uv;
	float lift;
};
struct Fade {
	float amount;
};
vec4 tinted(sampler2D t, vec2 uv) {
	return textureLod(t, uv * 2.0, 0.0) * vec4(1.0, 0.5, 0.5, 1.0);
}
vec4 fs(TexVaryings i, Fade fade, sampler2D albedo, sampler2D height) {
	return mix(tinted(albedo, i.uv), textureLod(height, i.uv, 0.0), vec4(fade.amount)) * i.lift;
}
layout(std140) uniform Fade_block {
	float amount;
} u_1;
uniform sampler2D tex_2;
uniform sampler2D tex_0;
in vec2 v_uv;
in float v_lift;
out vec4 out_color;
void main() {
	out_color = fs(TexVaryings(gl_FragCoord, v_uv, v_lift), Fade(u_1.amount), tex_2, tex_0);
}
