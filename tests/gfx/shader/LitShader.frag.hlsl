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
struct Material {
	float4 tint;
	int steps;
};
Material make_Material(float4 f0, int f1) {
	Material s;
	s.tint = f0;
	s.steps = f1;
	return s;
}
float posterize(float x, int steps) {
	if (steps < 2) {
		return x;
	}
	return floor(x * float(steps)) / float(steps - 1);
}
float4 fs(LitVaryings i, Material m) {
	float glow = 0.0;
	int t = 0;
	int t_2 = m.steps;
	while (t < t_2) {
		int k = t;
		t += 1;
		glow += 1.0 / float(k + 2);
	}
	float3 color = m.tint.xyz * (0.1 + posterize(i.shade, m.steps));
	if (i.uv.x > 0.5) {
		color = color.zyx;
	} else if (i.uv.y < 0.25) {
		color = 1.0 - color;
	}
	float check = ((int(i.uv.x * 8.0) % 2) == 0) ? 1.0 : 0.5;
	return float4(clamp((color * check) + (glow * 0.01), ((float3)0.0), ((float3)1.0)), m.tint.w);
}
cbuffer Material_block : register(b1) {
	float4 u_1_tint : packoffset(c0);
	int u_1_steps : packoffset(c1);
};
struct StageOut {
	float4 clip : SV_Position;
	float3 normal : TEXCOORD0;
	float2 uv : TEXCOORD1;
	float shade : TEXCOORD2;
};
float4 main(StageOut i) : SV_Target {
	return fs(make_LitVaryings(i.normal, i.clip, i.uv, i.shade), make_Material(u_1_tint, u_1_steps));
}
