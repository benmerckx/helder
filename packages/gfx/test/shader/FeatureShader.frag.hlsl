struct FeatureVaryings {
	float4 pos;
	float2 uv;
	float4 color;
	float mode;
};
FeatureVaryings make_FeatureVaryings(float4 f0, float2 f1, float4 f2, float f3) {
	FeatureVaryings s;
	s.pos = f0;
	s.uv = f1;
	s.color = f2;
	s.mode = f3;
	return s;
}
float4 fs(FeatureVaryings i, Texture2D mask, SamplerState mask_smp, Texture2D image, SamplerState image_smp) {
	float m = mask.SampleLevel(mask_smp, i.uv, 0.0).x;
	float4 c = image.SampleLevel(image_smp, i.uv, 0.0);
	if (i.mode < 0.5) {
		return i.color;
	}
	if (i.mode < 1.5) {
		return i.color * m;
	}
	return c * i.color;
}
Texture2D tex_0 : register(t0);
SamplerState smp_0 : register(s0);
Texture2D tex_1 : register(t1);
SamplerState smp_1 : register(s1);
struct StageOut {
	float4 pos : SV_Position;
	float2 uv : TEXCOORD0;
	float4 color : TEXCOORD1;
	float mode : TEXCOORD2;
};
float4 main(StageOut i) : SV_Target {
	return fs(make_FeatureVaryings(i.pos, i.uv, i.color, i.mode), tex_0, smp_0, tex_1, smp_1);
}
