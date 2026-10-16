struct FeatureVertex {
	float2 pos;
	float2 uv;
	float4 color;
	float mode;
};
FeatureVertex make_FeatureVertex(float2 f0, float2 f1, float4 f2, float f3) {
	FeatureVertex s;
	s.pos = f0;
	s.uv = f1;
	s.color = f2;
	s.mode = f3;
	return s;
}
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
FeatureVaryings vs(FeatureVertex v) {
	return make_FeatureVaryings(float4(v.pos, 0.0, 1.0), v.uv, v.color, v.mode);
}
struct StageIn {
	float2 pos : TEXCOORD0;
	float2 uv : TEXCOORD1;
	float4 color : TEXCOORD2;
	float mode : TEXCOORD3;
};
struct StageOut {
	float4 pos : SV_Position;
	float2 uv : TEXCOORD0;
	float4 color : TEXCOORD1;
	float mode : TEXCOORD2;
};
StageOut main(StageIn i) {
	FeatureVaryings r = vs(make_FeatureVertex(i.pos, i.uv, i.color, i.mode));
	StageOut o;
	o.pos = r.pos;
	o.uv = r.uv;
	o.color = r.color;
	o.mode = r.mode;
	return o;
}
