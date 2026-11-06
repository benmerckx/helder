struct SlotVaryings {
	clip: vec4f,
	uv: vec2f,
	tint: vec4f,
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
	var c: vec4f = plainColor(SlotSurface(i.uv), view);
	c = c * i.tint;
	var sum: f32 = 0.0;
	sum += 1.0;
	sum += 2.0;
	sum += 3.0;
	return c * sum;
}
@group(0) @binding(0) var<uniform> u_0: SlotView;
@fragment fn main(@builtin(position) in_clip: vec4f, @location(0) in_uv: vec2f, @location(1) in_tint: vec4f) -> @location(0) vec4f {
	return fs(SlotVaryings(in_clip, in_uv, in_tint), u_0);
}
