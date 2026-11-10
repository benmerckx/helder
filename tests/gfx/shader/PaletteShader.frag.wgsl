struct PaletteVaryings {
	pos: vec4f,
	index: f32,
}
struct PaletteBlock {
	scale: vec4f,
	colors: array<vec4f, 4>,
	turns: array<mat4x4f, 2>,
}
fn fs(i: PaletteVaryings, palette: PaletteBlock) -> vec4f {
	let k: i32 = i32(i.index + 0.5);
	let quarter: f32 = (atan2(1.0, 0.0) * 2.0) / 3.14159265358979312;
	return vec4f((palette.colors[k].xyz * vec3f(0.5, 1.0, 0.25)) * (quarter * palette.scale.x), 1.0);
}
@group(0) @binding(0) var<uniform> u_0: PaletteBlock;
@fragment fn main(@builtin(position) in_pos: vec4f, @location(0) in_index: f32) -> @location(0) vec4f {
	return fs(PaletteVaryings(in_pos, in_index), u_0);
}
