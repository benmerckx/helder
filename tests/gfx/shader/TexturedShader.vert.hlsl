struct TexVertex {
	float2 pos;
	float2 uv;
};
TexVertex make_TexVertex(float2 f0, float2 f1) {
	TexVertex s;
	s.pos = f0;
	s.uv = f1;
	return s;
}
struct TexVaryings {
	float4 pos;
	float2 uv;
	float lift;
};
TexVaryings make_TexVaryings(float4 f0, float2 f1, float f2) {
	TexVaryings s;
	s.pos = f0;
	s.uv = f1;
	s.lift = f2;
	return s;
}
TexVaryings vs(TexVertex v, Texture2D height, SamplerState height_smp) {
	float4 t = float4(v.pos, 0.0, 1.0);
	float2 t_2 = v.uv;
	return make_TexVaryings(t, t_2, height.SampleLevel(height_smp, v.uv, 0.0).x);
}
Texture2D tex_0 : register(t0);
SamplerState smp_0 : register(s0);
struct StageIn {
	float2 pos : TEXCOORD0;
	float2 uv : TEXCOORD1;
};
struct StageOut {
	float4 pos : SV_Position;
	float2 uv : TEXCOORD0;
	float lift : TEXCOORD1;
};
StageOut main(StageIn i) {
	TexVaryings r = vs(make_TexVertex(i.pos, i.uv), tex_0, smp_0);
	StageOut o;
	o.pos = r.pos;
	o.uv = r.uv;
	o.lift = r.lift;
	return o;
}
