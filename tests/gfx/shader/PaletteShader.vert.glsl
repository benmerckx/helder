#version 300 es
struct PaletteVertex {
	vec2 pos;
	float index;
};
struct PaletteBlock {
	vec4 scale;
	vec4[4] colors;
	mat4[2] turns;
};
struct PaletteVaryings {
	vec4 pos;
	float index;
};
PaletteVaryings vs(PaletteVertex v, PaletteBlock palette) {
	return PaletteVaryings(palette.turns[1] * vec4(v.pos, 0.0, 1.0), v.index);
}
layout(std140) uniform PaletteBlock_block {
	vec4 scale;
	vec4[4] colors;
	mat4[2] turns;
} u_0;
layout(location = 0) in vec2 in_pos;
layout(location = 1) in float in_index;
out float v_index;
uniform vec2 u_target;
void main() {
	PaletteVaryings r = vs(PaletteVertex(in_pos, in_index), PaletteBlock(u_0.scale, u_0.colors, u_0.turns));
	gl_Position = vec4(r.pos.x, -u_target.y * r.pos.y, 2.0 * r.pos.z - r.pos.w, r.pos.w);
	v_index = r.index;
}
