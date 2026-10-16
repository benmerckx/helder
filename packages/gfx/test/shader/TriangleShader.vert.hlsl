struct Vertex {
	float2 pos;
	float3 color;
};
Vertex make_Vertex(float2 f0, float3 f1) {
	Vertex s;
	s.pos = f0;
	s.color = f1;
	return s;
}
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
Varyings vs(Vertex v) {
	return make_Varyings(float4(v.pos, 0.0, 1.0), v.color);
}
struct StageIn {
	float2 pos : TEXCOORD0;
	float3 color : TEXCOORD1;
};
struct StageOut {
	float4 pos : SV_Position;
	float3 color : TEXCOORD0;
};
StageOut main(StageIn i) {
	Varyings r = vs(make_Vertex(i.pos, i.color));
	StageOut o;
	o.pos = r.pos;
	o.color = r.color;
	return o;
}
