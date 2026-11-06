struct SlotVertex {
	pos: vec2f,
}
struct SlotView {
	scale: vec4f,
}
struct SlotVaryings {
	clip: vec4f,
	uv: vec2f,
}
fn vs(v: SlotVertex, view: SlotView) -> SlotVaryings {
	let at: vec2f = v.pos * view.scale.xy;
	return SlotVaryings(vec4f(at, 0.0, 1.0), v.pos);
}
@group(0) @binding(0) var<uniform> u_0: SlotView;
struct StageOut {
	@builtin(position) clip: vec4f,
	@location(0) uv: vec2f,
}
@vertex fn main(@location(0) in_pos: vec2f) -> StageOut {
	let r = vs(SlotVertex(in_pos), u_0);
	return StageOut(r.clip, r.uv);
}
