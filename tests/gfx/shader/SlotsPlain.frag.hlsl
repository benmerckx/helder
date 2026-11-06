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
struct SlotView {
	float4 scale;
};
SlotView make_SlotView(float4 f0) {
	SlotView s;
	s.scale = f0;
	return s;
}
struct SlotSurface {
	float2 uv;
};
SlotSurface make_SlotSurface(float2 f0) {
	SlotSurface s;
	s.uv = f0;
	return s;
}
float4 plainColor(SlotSurface s, SlotView view) {
	return float4(s.uv, view.scale.x, 1.0);
}
float4 fs(SlotVaryings i, SlotView view) {
	float4 c = plainColor(make_SlotSurface(i.uv), view);
	float sum = 0.0;
	sum += 1.0;
	return c * sum;
}
cbuffer SlotView_block : register(b0) {
	float4 u_0_scale : packoffset(c0);
};
struct StageOut {
	float4 clip : SV_Position;
	float2 uv : TEXCOORD0;
};
float4 main(StageOut i) : SV_Target {
	return fs(make_SlotVaryings(i.clip, i.uv), make_SlotView(u_0_scale));
}
