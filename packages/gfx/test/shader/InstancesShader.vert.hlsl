struct InstanceVertex {
	float2 corner;
	float2 at;
	float size;
	float angle;
	float3 color;
};
InstanceVertex make_InstanceVertex(float2 f0, float2 f1, float f2, float f3, float3 f4) {
	InstanceVertex s;
	s.corner = f0;
	s.at = f1;
	s.size = f2;
	s.angle = f3;
	s.color = f4;
	return s;
}
struct InstanceField {
	float2 scale;
	float time;
};
InstanceField make_InstanceField(float2 f0, float f1) {
	InstanceField s;
	s.scale = f0;
	s.time = f1;
	return s;
}
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
InstanceVaryings vs(InstanceVertex v, InstanceField f) {
	float a = v.angle + f.time;
	float c = cos(a);
	float s = sin(a);
	float2 p = (float2((v.corner.x * c) - (v.corner.y * s), (v.corner.x * s) + (v.corner.y * c)) * v.size) + v.at;
	return make_InstanceVaryings(float4(p * f.scale, 0.0, 1.0), v.color, v.corner);
}
cbuffer InstanceField_block : register(b0) {
	float2 u_0_scale : packoffset(c0);
	float u_0_time : packoffset(c0.z);
};
struct StageIn {
	float2 corner : TEXCOORD0;
	float2 at : TEXCOORD1;
	float size : TEXCOORD2;
	float angle : TEXCOORD3;
	float3 color : TEXCOORD4;
};
struct StageOut {
	float4 pos : SV_Position;
	float3 color : TEXCOORD0;
	float2 corner : TEXCOORD1;
};
StageOut main(StageIn i) {
	InstanceVaryings r = vs(make_InstanceVertex(i.corner, i.at, i.size, i.angle, i.color), make_InstanceField(u_0_scale, u_0_time));
	StageOut o;
	o.pos = r.pos;
	o.color = r.color;
	o.corner = r.corner;
	return o;
}
