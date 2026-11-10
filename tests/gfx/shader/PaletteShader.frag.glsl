#version 300 es
precision highp float;
precision highp int;
struct PaletteVaryings {
	vec4 pos;
	float index;
};
struct PaletteBlock {
	vec4 scale;
	vec4[4] colors;
	mat4[2] turns;
};
vec4 fs(PaletteVaryings i, PaletteBlock palette) {
	int k = int(i.index + 0.5);
	float quarter = (atan(1.0, 0.0) * 2.0) / 3.14159265358979312;
	return vec4((palette.colors[k].xyz * vec3(0.5, 1.0, 0.25)) * (quarter * palette.scale.x), 1.0);
}
layout(std140) uniform PaletteBlock_block {
	vec4 scale;
	vec4[4] colors;
	mat4[2] turns;
} u_0;
in float v_index;
uniform vec2 u_target;
out vec4 out_color;
void main() {
	out_color = fs(PaletteVaryings(vec4(gl_FragCoord.x, u_target.x + u_target.y * gl_FragCoord.y, gl_FragCoord.zw), v_index), PaletteBlock(u_0.scale, u_0.colors, u_0.turns));
}
