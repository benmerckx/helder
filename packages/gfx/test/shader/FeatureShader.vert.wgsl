struct FeatureVertex {
	pos: vec2f,
	uv: vec2f,
	color: vec4f,
	mode: f32,
}
struct FeatureVaryings {
	pos: vec4f,
	uv: vec2f,
	color: vec4f,
	mode: f32,
}
fn vs(v: FeatureVertex) -> FeatureVaryings {
	return FeatureVaryings(vec4f(v.pos, 0.0, 1.0), v.uv, v.color, v.mode);
}
struct StageOut {
	@builtin(position) pos: vec4f,
	@location(0) uv: vec2f,
	@location(1) color: vec4f,
	@location(2) mode: f32,
}
@vertex fn main(@location(0) in_pos: vec2f, @location(1) in_uv: vec2f, @location(2) in_color: vec4f, @location(3) in_mode: f32) -> StageOut {
	let r = vs(FeatureVertex(in_pos, in_uv, in_color, in_mode));
	return StageOut(r.pos, r.uv, r.color, r.mode);
}
