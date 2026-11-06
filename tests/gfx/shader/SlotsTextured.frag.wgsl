diagnostic(off, derivative_uniformity);
struct SlotVaryings {
	clip: vec4f,
	uv: vec2f,
}
struct SlotView {
	scale: vec4f,
}
struct SlotSurface {
	uv: vec2f,
}
fn color(s: SlotSurface, image: texture_2d<f32>, image_smp: sampler) -> vec4f {
	return textureSample(image, image_smp, s.uv);
}
fn fs(i: SlotVaryings, view: SlotView, image: texture_2d<f32>, image_smp: sampler) -> vec4f {
	let c: vec4f = color(SlotSurface(i.uv), image, image_smp);
	var sum: f32 = 0.0;
	sum += 1.0;
	return c * sum;
}
@group(0) @binding(0) var<uniform> u_0: SlotView;
@group(0) @binding(1) var tex_1: texture_2d<f32>;
@group(0) @binding(17) var smp_1: sampler;
@fragment fn main(@builtin(position) in_clip: vec4f, @location(0) in_uv: vec2f) -> @location(0) vec4f {
	return fs(SlotVaryings(in_clip, in_uv), u_0, tex_1, smp_1);
}
