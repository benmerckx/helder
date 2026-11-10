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
float4 fs(PaletteVaryings i, PaletteBlock palette) {
	int k = int(i.index + 0.5);
	float quarter = (atan2(1.0, 0.0) * 2.0) / 3.14159265358979312;
	return float4((palette.colors[k].xyz * float3(0.5, 1.0, 0.25)) * (quarter * palette.scale.x), 1.0);
}
cbuffer PaletteBlock_block : register(b0) {
	float4 u_0_scale : packoffset(c0);
	float4 u_0_colors[4] : packoffset(c1);
	row_major float4x4 u_0_turns[2] : packoffset(c5);
};
struct StageOut {
	float4 pos : SV_Position;
	float index : TEXCOORD0;
};
float4 main(StageOut i) : SV_Target {
	return fs(make_PaletteVaryings(i.pos, i.index), make_PaletteBlock(u_0_scale, u_0_colors, u_0_turns));
}
