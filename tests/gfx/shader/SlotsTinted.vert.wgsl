struct SlotVertex {
	pos: vec2f,
	tint: vec4f,
	shift: vec2f,
}
struct SlotView {
	scale: vec4f,
}
struct SlotVaryings {
	clip: vec4f,
	uv: vec2f,
	tint: vec4f,
}
fn vs(v: SlotVertex, view: SlotView) -> SlotVaryings {
	var at: vec2f = v.pos * view.scale.xy;
	at = at + v.shift;
	return SlotVaryings(vec4f(at, 0.0, 1.0), v.pos, v.tint);
}
@group(0) @binding(0) var<uniform> u_0: SlotView;
struct StageOut {
	@builtin(position) clip: vec4f,
	@location(0) uv: vec2f,
	@location(1) tint: vec4f,
}
@vertex fn main(@location(0) in_pos: vec2f, @location(1) in_tint: vec4f, @location(2) in_shift: vec2f) -> StageOut {
	let r = vs(SlotVertex(in_pos, in_tint, in_shift), u_0);
	return StageOut(r.clip, r.uv, r.tint);
}
