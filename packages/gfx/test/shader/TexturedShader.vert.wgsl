struct TexVertex {
	pos: vec2f,
	uv: vec2f,
}
struct TexVaryings {
	pos: vec4f,
	uv: vec2f,
	lift: f32,
}
fn vs(v: TexVertex, height: texture_2d<f32>, height_smp: sampler) -> TexVaryings {
	let t: vec4f = vec4f(v.pos, 0.0, 1.0);
	let t_2: vec2f = v.uv;
	return TexVaryings(t, t_2, textureSampleLevel(height, height_smp, v.uv, 0.0).x);
}
@group(0) @binding(0) var tex_0: texture_2d<f32>;
@group(0) @binding(16) var smp_0: sampler;
struct StageOut {
	@builtin(position) pos: vec4f,
	@location(0) uv: vec2f,
	@location(1) lift: f32,
}
@vertex fn main(@location(0) in_pos: vec2f, @location(1) in_uv: vec2f) -> StageOut {
	let r = vs(TexVertex(in_pos, in_uv), tex_0, smp_0);
	return StageOut(r.pos, r.uv, r.lift);
}
