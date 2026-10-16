struct BuiltinVaryings {
	pos: vec4f,
	a: f32,
	b: vec2f,
}
fn fs(i: BuiltinVaryings) -> vec4f {
	let x: f32 = i.a;
	let v2: vec2f = i.b;
	let v3: vec3f = vec3f(v2, x);
	let v4: vec4f = vec4f(v3, 1.0);
	var s: f32 = ((((((((((abs(x) + sign(x)) + floor(x)) + ceil(x)) + fract(x)) + sqrt(x)) + inverseSqrt(x + 1.0)) + sin(x)) + cos(x)) + tan(x)) + exp(x)) + log(x + 1.0);
	s += (((((min(x, 1.0) + max(x, 0.0)) + pow(x, 2.0)) + step(0.5, x)) + mix(0.0, 1.0, x)) + clamp(x, 0.0, 1.0)) + smoothstep(0.0, 1.0, x);
	s += ((((((sqrt(x) + abs(-x)) + min(x, 2.0)) + pow(2.0, x)) + floor(x)) + f32(i32(floor(x)))) + f32(i32(x * 3.0))) + 3.14159265358979312;
	var w: vec3f = ((((((((((abs(v3) + sign(v3)) + floor(v3)) + ceil(v3)) + fract(v3)) + sqrt(v3)) + inverseSqrt(v3 + 1.0)) + sin(v3)) + cos(v3)) + tan(v3)) + exp(v3)) + log(v3 + 1.0);
	let lhs: f32 = 0.5;
	let rhs: vec3f = v3;
	w = w + (((((min(v3, v3.zyx) + max(v3, rhs * lhs)) + pow(v3, vec3f(2.0))) + step(v3, vec3f(0.5))) + mix(v3, -v3, vec3f(0.5))) + mix(v3, v3.yzx, v3));
	w = w + ((((clamp(v3, vec3f(0.0), vec3f(1.0)) + clamp(v3, v3.yzx, v3.zxy)) + smoothstep(vec3f(0.0), vec3f(1.0), v3)) + smoothstep(vec3f(0.0), vec3f(1.0), v3)) + reflect(v3, normalize(v3.zyx)));
	w = w + ((((((cross(v3, v3.yzx) + vec3f(dot(v3, v3), length(v3), distance(v3, v3.zyx))) + vec3f(1.0, v2)) + vec3f(v2.yx, 1.0)) + (v3 / 2.0)) - (1.0 / (v3 + 1.0))) - 1.0);
	var n: i32 = 0;
	var k: i32 = 7;
	while (n < 10) {
		n += 1;
		if (n == 3) {
			continue;
		}
		if ((n > 8) || (((k & 1) == 0) && (n != 5))) {
			break;
		}
		k = ((k << u32(1)) | n) ^ (k >> u32(1));
	}
	let t: f32 = select(-x, x, x > 0.5);
	return ((((vec4f(w, s) * 0.01) + (v4 * (f32(n + (k % 5)) + t))) + vec4f(v2, v2)) + vec4f(x, v3)) - vec4f(x);
}
@fragment fn main(@builtin(position) in_pos: vec4f, @location(0) in_a: f32, @location(1) in_b: vec2f) -> @location(0) vec4f {
	return fs(BuiltinVaryings(in_pos, in_a, in_b));
}
