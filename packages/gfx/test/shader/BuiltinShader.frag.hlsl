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
float4 fs(BuiltinVaryings i) {
	float x = i.a;
	float2 v2 = i.b;
	float3 v3 = float3(v2, x);
	float4 v4 = float4(v3, 1.0);
	float s = ((((((((((abs(x) + ((float)sign(x))) + floor(x)) + ceil(x)) + frac(x)) + sqrt(x)) + rsqrt(x + 1.0)) + sin(x)) + cos(x)) + tan(x)) + exp(x)) + log(x + 1.0);
	s += (((((min(x, 1.0) + max(x, 0.0)) + pow(x, 2.0)) + step(0.5, x)) + lerp(0.0, 1.0, x)) + clamp(x, 0.0, 1.0)) + smoothstep(0.0, 1.0, x);
	s += ((((((sqrt(x) + abs(-x)) + min(x, 2.0)) + pow(2.0, x)) + floor(x)) + float(int(floor(x)))) + float(int(x * 3.0))) + 3.14159265358979312;
	float3 w = ((((((((((abs(v3) + ((float3)sign(v3))) + floor(v3)) + ceil(v3)) + frac(v3)) + sqrt(v3)) + rsqrt(v3 + 1.0)) + sin(v3)) + cos(v3)) + tan(v3)) + exp(v3)) + log(v3 + 1.0);
	float lhs = 0.5;
	float3 rhs = v3;
	w = w + (((((min(v3, v3.zyx) + max(v3, rhs * lhs)) + pow(v3, ((float3)2.0))) + step(v3, ((float3)0.5))) + lerp(v3, -v3, ((float3)0.5))) + lerp(v3, v3.yzx, v3));
	w = w + ((((clamp(v3, ((float3)0.0), ((float3)1.0)) + clamp(v3, v3.yzx, v3.zxy)) + smoothstep(((float3)0.0), ((float3)1.0), v3)) + smoothstep(((float3)0.0), ((float3)1.0), v3)) + reflect(v3, normalize(v3.zyx)));
	w = w + ((((((cross(v3, v3.yzx) + float3(dot(v3, v3), length(v3), distance(v3, v3.zyx))) + float3(1.0, v2)) + float3(v2.yx, 1.0)) + (v3 / 2.0)) - (1.0 / (v3 + 1.0))) - 1.0);
	int n = 0;
	int k = 7;
	while (n < 10) {
		n += 1;
		if (n == 3) {
			continue;
		}
		if ((n > 8) || (((k & 1) == 0) && (n != 5))) {
			break;
		}
		k = ((k << 1) | n) ^ (k >> 1);
	}
	float t = (x > 0.5) ? x : (-x);
	return ((((float4(w, s) * 0.01) + (v4 * (float(n + (k % 5)) + t))) + float4(v2, v2)) + float4(x, v3)) - ((float4)x);
}
struct StageOut {
	float4 pos : SV_Position;
	float a : TEXCOORD0;
	float2 b : TEXCOORD1;
};
float4 main(StageOut i) : SV_Target {
	return fs(make_BuiltinVaryings(i.pos, i.a, i.b));
}
