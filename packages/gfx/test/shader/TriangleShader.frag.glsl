#version 300 es
precision highp float;
precision highp int;
struct Varyings {
	vec4 pos;
	vec3 color;
};
vec4 fs(Varyings i) {
	return vec4(i.color, 1.0);
}
in vec3 v_color;
out vec4 out_color;
void main() {
	out_color = fs(Varyings(gl_FragCoord, v_color));
}
