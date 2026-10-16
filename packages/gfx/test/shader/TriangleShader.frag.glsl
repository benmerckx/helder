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
uniform float u_target_height;
out vec4 out_color;
void main() {
	out_color = fs(Varyings(vec4(gl_FragCoord.x, u_target_height - gl_FragCoord.y, gl_FragCoord.zw), v_color));
}
