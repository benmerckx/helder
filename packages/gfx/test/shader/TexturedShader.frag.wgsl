diagnostic(off, derivative_uniformity);
struct TexVaryings {
	pos: vec4f,
	uv: vec2f,
	lift: f32,
}
struct Fade {
	amount: f32,
}
fn tinted(t: texture_2d<f32>, t_smp: sampler, uv: vec2f) -> vec4f {
	return textureSample(t, t_smp, uv * 2.0) * vec4f(1.0, 0.5, 0.5, 1.0);
}
fn fs(i: TexVaryings, fade: Fade, albedo: texture_2d<f32>, albedo_smp: sampler, height: texture_2d<f32>, height_smp: sampler) -> vec4f {
	return mix(tinted(albedo, albedo_smp, i.uv), textureSampleLevel(height, height_smp, i.uv, 1.5), vec4f(fade.amount)) * i.lift;
}
@group(0) @binding(1) var<uniform> u_1: Fade;
@group(0) @binding(2) var tex_2: texture_2d<f32>;
@group(0) @binding(18) var smp_2: sampler;
@group(0) @binding(0) var tex_0: texture_2d<f32>;
@group(0) @binding(16) var smp_0: sampler;
@fragment fn main(@builtin(position) in_pos: vec4f, @location(0) in_uv: vec2f, @location(1) in_lift: f32) -> @location(0) vec4f {
	return fs(TexVaryings(in_pos, in_uv, in_lift), u_1, tex_2, smp_2, tex_0, smp_0);
}
