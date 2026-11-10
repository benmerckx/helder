struct PaletteVertex {
	pos: vec2f,
	index: f32,
}
struct PaletteBlock {
	scale: vec4f,
	colors: array<vec4f, 4>,
	turns: array<mat4x4f, 2>,
}
struct PaletteVaryings {
	pos: vec4f,
	index: f32,
}
fn vs(v: PaletteVertex, palette: PaletteBlock) -> PaletteVaryings {
	return PaletteVaryings(palette.turns[1] * vec4f(v.pos, 0.0, 1.0), v.index);
}
@group(0) @binding(0) var<uniform> u_0: PaletteBlock;
struct StageOut {
	@builtin(position) pos: vec4f,
	@location(0) index: f32,
}
@vertex fn main(@location(0) in_pos: vec2f, @location(1) in_index: f32) -> StageOut {
	let r = vs(PaletteVertex(in_pos, in_index), u_0);
	return StageOut(r.pos, r.index);
}
