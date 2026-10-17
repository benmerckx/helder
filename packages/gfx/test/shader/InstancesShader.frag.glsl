#version 300 es
precision highp float;
precision highp int;
struct InstanceVaryings {
	vec4 pos;
	vec3 color;
	vec2 corner;
};
vec4 fs(InstanceVaryings i) {
	return vec4(i.color * (1.0 - (0.3 * length(i.corner))), 1.0);
}
in vec3 v_color;
in vec2 v_corner;
uniform vec2 u_target;
out vec4 out_color;
void main() {
	out_color = fs(InstanceVaryings(vec4(gl_FragCoord.x, u_target.x + u_target.y * gl_FragCoord.y, gl_FragCoord.zw), v_color, v_corner));
}
