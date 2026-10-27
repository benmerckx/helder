struct Varyings {
	float4 pos;
	float3 color;
};
Varyings make_Varyings(float4 f0, float3 f1) {
	Varyings s;
	s.pos = f0;
	s.color = f1;
	return s;
}
float4 fs(Varyings i) {
	return float4(i.color, 1.0);
}
struct StageOut {
	float4 pos : SV_Position;
	float3 color : TEXCOORD0;
};
float4 main(StageOut i) : SV_Target {
	return fs(make_Varyings(i.pos, i.color));
}
