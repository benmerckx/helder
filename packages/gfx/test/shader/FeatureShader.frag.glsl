#version 300 es
precision highp float;
precision highp int;
struct FeatureVaryings {
	vec4 pos;
	vec2 uv;
	vec4 color;
	float mode;
};
vec4 fs(FeatureVaryings i, sampler2D mask, sampler2D image) {
	float m = textureLod(mask, i.uv, 0.0).x;
	vec4 c = textureLod(image, i.uv, 0.0);
	if (i.mode < 0.5) {
		return i.color;
	}
	if (i.mode < 1.5) {
		return i.color * m;
	}
	return c * i.color;
}
uniform sampler2D tex_0;
uniform sampler2D tex_1;
in vec2 v_uv;
in vec4 v_color;
in float v_mode;
out vec4 out_color;
void main() {
	out_color = fs(FeatureVaryings(gl_FragCoord, v_uv, v_color, v_mode), tex_0, tex_1);
}
