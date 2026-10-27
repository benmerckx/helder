struct Vertex {
	pos: vec2f,
	color: vec3f,
}
struct Varyings {
	pos: vec4f,
	color: vec3f,
}
fn vs(v: Vertex) -> Varyings {
	return Varyings(vec4f(v.pos, 0.0, 1.0), v.color);
}
struct StageOut {
	@builtin(position) pos: vec4f,
	@location(0) color: vec3f,
}
@vertex fn main(@location(0) in_pos: vec2f, @location(1) in_color: vec3f) -> StageOut {
	let r = vs(Vertex(in_pos, in_color));
	return StageOut(r.pos, r.color);
}
