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
struct Fade {
	float amount;
};
Fade make_Fade(float f0) {
	Fade s;
	s.amount = f0;
	return s;
}
float4 tinted(Texture2D t, SamplerState t_smp, float2 uv) {
	return t.SampleLevel(t_smp, uv * 2.0, 0.0) * float4(1.0, 0.5, 0.5, 1.0);
}
float4 fs(TexVaryings i, Fade fade, Texture2D albedo, SamplerState albedo_smp, Texture2D height, SamplerState height_smp) {
	return lerp(tinted(albedo, albedo_smp, i.uv), height.SampleLevel(height_smp, i.uv, 0.0), ((float4)fade.amount)) * i.lift;
}
cbuffer Fade_block : register(b1) {
	float u_1_amount : packoffset(c0);
};
Texture2D tex_2 : register(t2);
SamplerState smp_2 : register(s2);
Texture2D tex_0 : register(t0);
SamplerState smp_0 : register(s0);
struct StageOut {
	float4 pos : SV_Position;
	float2 uv : TEXCOORD0;
	float lift : TEXCOORD1;
};
float4 main(StageOut i) : SV_Target {
	return fs(make_TexVaryings(i.pos, i.uv, i.lift), make_Fade(u_1_amount), tex_2, smp_2, tex_0, smp_0);
}
