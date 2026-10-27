struct LitVaryings {
	normal: vec3f,
	clip: vec4f,
	uv: vec2f,
	shade: f32,
}
struct Material {
	tint: vec4f,
	steps: i32,
}
fn posterize(x: f32, steps: i32) -> f32 {
	if (steps < 2) {
		return x;
	}
	return floor(x * f32(steps)) / f32(steps - 1);
}
fn fs(i: LitVaryings, m: Material) -> vec4f {
	var glow: f32 = 0.0;
	var t: i32 = 0;
	let t_2: i32 = m.steps;
	while (t < t_2) {
		let k: i32 = t;
		t += 1;
		glow += 1.0 / f32(k + 2);
	}
	var color: vec3f = m.tint.xyz * (0.1 + posterize(i.shade, m.steps));
	if (i.uv.x > 0.5) {
		color = color.zyx;
	} else if (i.uv.y < 0.25) {
		color = 1.0 - color;
	}
	let check: f32 = select(0.5, 1.0, (i32(i.uv.x * 8.0) % 2) == 0);
	return vec4f(clamp((color * check) + (glow * 0.01), vec3f(0.0), vec3f(1.0)), m.tint.w);
}
@group(0) @binding(1) var<uniform> u_1: Material;
@fragment fn main(@builtin(position) in_clip: vec4f, @location(0) in_normal: vec3f, @location(1) in_uv: vec2f, @location(2) in_shade: f32) -> @location(0) vec4f {
	return fs(LitVaryings(in_normal, in_clip, in_uv, in_shade), u_1);
}
