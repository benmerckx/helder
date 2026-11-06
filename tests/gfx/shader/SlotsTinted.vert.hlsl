struct SlotVertex {
	float2 pos;
	float4 tint;
	float2 shift;
};
SlotVertex make_SlotVertex(float2 f0, float4 f1, float2 f2) {
	SlotVertex s;
	s.pos = f0;
	s.tint = f1;
	s.shift = f2;
	return s;
}
struct SlotView {
	float4 scale;
};
SlotView make_SlotView(float4 f0) {
	SlotView s;
	s.scale = f0;
	return s;
}
struct SlotVaryings {
	float4 clip;
	float2 uv;
	float4 tint;
};
SlotVaryings make_SlotVaryings(float4 f0, float2 f1, float4 f2) {
	SlotVaryings s;
	s.clip = f0;
	s.uv = f1;
	s.tint = f2;
	return s;
}
SlotVaryings vs(SlotVertex v, SlotView view) {
	float2 at = v.pos * view.scale.xy;
	at = at + v.shift;
	return make_SlotVaryings(float4(at, 0.0, 1.0), v.pos, v.tint);
}
cbuffer SlotView_block : register(b0) {
	float4 u_0_scale : packoffset(c0);
};
struct StageIn {
	float2 pos : TEXCOORD0;
	float4 tint : TEXCOORD1;
	float2 shift : TEXCOORD2;
};
struct StageOut {
	float4 clip : SV_Position;
	float2 uv : TEXCOORD0;
	float4 tint : TEXCOORD1;
};
StageOut main(StageIn i) {
	SlotVaryings r = vs(make_SlotVertex(i.pos, i.tint, i.shift), make_SlotView(u_0_scale));
	StageOut o;
	o.clip = r.clip;
	o.uv = r.uv;
	o.tint = r.tint;
	return o;
}
