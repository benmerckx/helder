struct SlotVertex {
	float2 pos;
};
SlotVertex make_SlotVertex(float2 f0) {
	SlotVertex s;
	s.pos = f0;
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
};
SlotVaryings make_SlotVaryings(float4 f0, float2 f1) {
	SlotVaryings s;
	s.clip = f0;
	s.uv = f1;
	return s;
}
SlotVaryings vs(SlotVertex v, SlotView view) {
	float2 at = v.pos * view.scale.xy;
	return make_SlotVaryings(float4(at, 0.0, 1.0), v.pos);
}
cbuffer SlotView_block : register(b0) {
	float4 u_0_scale : packoffset(c0);
};
struct StageIn {
	float2 pos : TEXCOORD0;
};
struct StageOut {
	float4 clip : SV_Position;
	float2 uv : TEXCOORD0;
};
StageOut main(StageIn i) {
	SlotVaryings r = vs(make_SlotVertex(i.pos), make_SlotView(u_0_scale));
	StageOut o;
	o.clip = r.clip;
	o.uv = r.uv;
	return o;
}
