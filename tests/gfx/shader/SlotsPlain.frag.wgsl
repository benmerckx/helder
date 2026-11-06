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
fn plainColor(s: SlotSurface, view: SlotView) -> vec4f {
	return vec4f(s.uv, view.scale.x, 1.0);
}
fn fs(i: SlotVaryings, view: SlotView) -> vec4f {
	let c: vec4f = plainColor(SlotSurface(i.uv), view);
	var sum: f32 = 0.0;
	sum += 1.0;
	return c * sum;
}
@group(0) @binding(0) var<uniform> u_0: SlotView;
@fragment fn main(@builtin(position) in_clip: vec4f, @location(0) in_uv: vec2f) -> @location(0) vec4f {
	return fs(SlotVaryings(in_clip, in_uv), u_0);
}
