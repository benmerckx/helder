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
	return texture(t, uv * 2.0) * vec4(1.0, 0.5, 0.5, 1.0);
}
vec4 fs(TexVaryings i, Fade fade, sampler2D albedo, sampler2D height) {
	return mix(tinted(albedo, i.uv), textureLod(height, i.uv, 1.5), vec4(fade.amount)) * i.lift;
}
layout(std140) uniform Fade_block {
	float amount;
} u_1;
uniform sampler2D tex_2;
uniform sampler2D tex_0;
in vec2 v_uv;
in float v_lift;
uniform vec2 u_target;
out vec4 out_color;
void main() {
	out_color = fs(TexVaryings(vec4(gl_FragCoord.x, u_target.x + u_target.y * gl_FragCoord.y, gl_FragCoord.zw), v_uv, v_lift), Fade(u_1.amount), tex_2, tex_0);
}
