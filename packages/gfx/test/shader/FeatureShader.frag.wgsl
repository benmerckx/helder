struct FeatureVaryings {
	pos: vec4f,
	uv: vec2f,
	color: vec4f,
	mode: f32,
}
fn fs(i: FeatureVaryings, mask: texture_2d<f32>, mask_smp: sampler, image: texture_2d<f32>, image_smp: sampler) -> vec4f {
	let m: f32 = textureSampleLevel(mask, mask_smp, i.uv, 0.0).x;
	let c: vec4f = textureSampleLevel(image, image_smp, i.uv, 0.0);
	if (i.mode < 0.5) {
		return i.color;
	}
	if (i.mode < 1.5) {
		return i.color * m;
	}
	return c * i.color;
}
@group(0) @binding(16) var tex_0: texture_2d<f32>;
@group(0) @binding(17) var smp_0: sampler;
@group(0) @binding(18) var tex_1: texture_2d<f32>;
@group(0) @binding(19) var smp_1: sampler;
@fragment fn main(@builtin(position) in_pos: vec4f, @location(0) in_uv: vec2f, @location(1) in_color: vec4f, @location(2) in_mode: f32) -> @location(0) vec4f {
	return fs(FeatureVaryings(in_pos, in_uv, in_color, in_mode), tex_0, smp_0, tex_1, smp_1);
}
