struct PaletteVertex {
	float2 pos;
	float index;
};
PaletteVertex make_PaletteVertex(float2 f0, float f1) {
	PaletteVertex s;
	s.pos = f0;
	s.index = f1;
	return s;
}
struct PaletteBlock {
	float4 scale;
	float4 colors[4];
	float4x4 turns[2];
};
PaletteBlock make_PaletteBlock(float4 f0, float4 f1[4], float4x4 f2[2]) {
	PaletteBlock s;
	s.scale = f0;
	s.colors = f1;
	s.turns = f2;
	return s;
}
struct PaletteVaryings {
	float4 pos;
	float index;
};
PaletteVaryings make_PaletteVaryings(float4 f0, float f1) {
	PaletteVaryings s;
	s.pos = f0;
	s.index = f1;
	return s;
}
PaletteVaryings vs(PaletteVertex v, PaletteBlock palette) {
	return make_PaletteVaryings(mul(float4(v.pos, 0.0, 1.0), palette.turns[1]), v.index);
}
cbuffer PaletteBlock_block : register(b0) {
	float4 u_0_scale : packoffset(c0);
	float4 u_0_colors[4] : packoffset(c1);
	row_major float4x4 u_0_turns[2] : packoffset(c5);
};
struct StageIn {
	float2 pos : TEXCOORD0;
	float index : TEXCOORD1;
};
struct StageOut {
	float4 pos : SV_Position;
	float index : TEXCOORD0;
};
StageOut main(StageIn i) {
	PaletteVaryings r = vs(make_PaletteVertex(i.pos, i.index), make_PaletteBlock(u_0_scale, u_0_colors, u_0_turns));
	StageOut o;
	o.pos = r.pos;
	o.index = r.index;
	return o;
}
