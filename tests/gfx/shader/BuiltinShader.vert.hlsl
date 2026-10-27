struct BuiltinVertex {
	float4 pos;
};
BuiltinVertex make_BuiltinVertex(float4 f0) {
	BuiltinVertex s;
	s.pos = f0;
	return s;
}
struct BuiltinVaryings {
	float4 pos;
	float a;
	float2 b;
};
BuiltinVaryings make_BuiltinVaryings(float4 f0, float f1, float2 f2) {
	BuiltinVaryings s;
	s.pos = f0;
	s.a = f1;
	s.b = f2;
	return s;
}
BuiltinVaryings vs(BuiltinVertex v) {
	float4x4 m = mul(float4x4(float4(0.5, 0.0, 0.0, 0.0), float4(0.0, 0.5, 0.0, 0.0), float4(0.0, 0.0, 0.5, 0.0), float4(0.0, 0.0, 0.0, 0.5)), float4x4(float4(1.0, 0.0, 0.0, 0.0), float4(0.0, 1.0, 0.0, 0.0), float4(0.0, 0.0, 1.0, 0.0), float4(v.pos.xyz, 1.0)));
	float4 t = (mul(v.pos, m)) + (m[3] * 0.0);
	float t_2 = v.pos.w;
	return make_BuiltinVaryings(t, t_2, v.pos.xy);
}
struct StageIn {
	float4 pos : TEXCOORD0;
};
struct StageOut {
	float4 pos : SV_Position;
	float a : TEXCOORD0;
	float2 b : TEXCOORD1;
};
StageOut main(StageIn i) {
	BuiltinVaryings r = vs(make_BuiltinVertex(i.pos));
	StageOut o;
	o.pos = r.pos;
	o.a = r.a;
	o.b = r.b;
	return o;
}
