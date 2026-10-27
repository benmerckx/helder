struct LitVertex {
	float3 pos;
	float3 normal;
	float2 uv;
};
LitVertex make_LitVertex(float3 f0, float3 f1, float2 f2) {
	LitVertex s;
	s.pos = f0;
	s.normal = f1;
	s.uv = f2;
	return s;
}
struct Camera {
	float4x4 viewProj;
	float3 eye;
	float time;
};
Camera make_Camera(float4x4 f0, float3 f1, float f2) {
	Camera s;
	s.viewProj = f0;
	s.eye = f1;
	s.time = f2;
	return s;
}
struct LitVaryings {
	float3 normal;
	float4 clip;
	float2 uv;
	float shade;
};
LitVaryings make_LitVaryings(float3 f0, float4 f1, float2 f2, float f3) {
	LitVaryings s;
	s.normal = f0;
	s.clip = f1;
	s.uv = f2;
	s.shade = f3;
	return s;
}
float lambert(float3 n, float3 l) {
	return max(dot(normalize(n), normalize(l)), 0.0);
}
LitVaryings vs(LitVertex v, Camera cam) {
	float4 clip = mul(float4(v.pos, 1.0), cam.viewProj);
	float wobble = sin(cam.time + (v.pos.x * 3.0)) * 0.05;
	float3 t = v.normal;
	float4 t_2 = clip + float4(wobble, 0.0, 0.0, 0.0);
	float2 t_3 = v.uv.yx;
	return make_LitVaryings(t, t_2, t_3, lambert(v.normal, cam.eye - v.pos));
}
cbuffer Camera_block : register(b0) {
	row_major float4x4 u_0_viewProj : packoffset(c0);
	float3 u_0_eye : packoffset(c4);
	float u_0_time : packoffset(c4.w);
};
struct StageIn {
	float3 pos : TEXCOORD0;
	float3 normal : TEXCOORD1;
	float2 uv : TEXCOORD2;
};
struct StageOut {
	float4 clip : SV_Position;
	float3 normal : TEXCOORD0;
	float2 uv : TEXCOORD1;
	float shade : TEXCOORD2;
};
StageOut main(StageIn i) {
	LitVaryings r = vs(make_LitVertex(i.pos, i.normal, i.uv), make_Camera(u_0_viewProj, u_0_eye, u_0_time));
	StageOut o;
	o.clip = r.clip;
	o.normal = r.normal;
	o.uv = r.uv;
	o.shade = r.shade;
	return o;
}
