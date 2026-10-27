struct InstanceVaryings {
	float4 pos;
	float3 color;
	float2 corner;
};
InstanceVaryings make_InstanceVaryings(float4 f0, float3 f1, float2 f2) {
	InstanceVaryings s;
	s.pos = f0;
	s.color = f1;
	s.corner = f2;
	return s;
}
float4 fs(InstanceVaryings i) {
	return float4(i.color * (1.0 - (0.3 * length(i.corner))), 1.0);
}
struct StageOut {
	float4 pos : SV_Position;
	float3 color : TEXCOORD0;
	float2 corner : TEXCOORD1;
};
float4 main(StageOut i) : SV_Target {
	return fs(make_InstanceVaryings(i.pos, i.color, i.corner));
}
