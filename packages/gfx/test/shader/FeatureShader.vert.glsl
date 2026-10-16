#version 300 es
struct FeatureVertex {
	vec2 pos;
	vec2 uv;
	vec4 color;
	float mode;
};
struct FeatureVaryings {
	vec4 pos;
	vec2 uv;
	vec4 color;
	float mode;
};
FeatureVaryings vs(FeatureVertex v) {
	return FeatureVaryings(vec4(v.pos, 0.0, 1.0), v.uv, v.color, v.mode);
}
layout(location = 0) in vec2 in_pos;
layout(location = 1) in vec2 in_uv;
layout(location = 2) in vec4 in_color;
layout(location = 3) in float in_mode;
out vec2 v_uv;
out vec4 v_color;
out float v_mode;
void main() {
	FeatureVaryings r = vs(FeatureVertex(in_pos, in_uv, in_color, in_mode));
	gl_Position = r.pos;
	v_uv = r.uv;
	v_color = r.color;
	v_mode = r.mode;
}
