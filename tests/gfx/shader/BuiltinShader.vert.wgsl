struct BuiltinVertex {
	pos: vec4f,
}
struct BuiltinVaryings {
	pos: vec4f,
	a: f32,
	b: vec2f,
}
fn vs(v: BuiltinVertex) -> BuiltinVaryings {
	let m: mat4x4f = mat4x4f(vec4f(1.0, 0.0, 0.0, 0.0), vec4f(0.0, 1.0, 0.0, 0.0), vec4f(0.0, 0.0, 1.0, 0.0), vec4f(v.pos.xyz, 1.0)) * mat4x4f(vec4f(0.5, 0.0, 0.0, 0.0), vec4f(0.0, 0.5, 0.0, 0.0), vec4f(0.0, 0.0, 0.5, 0.0), vec4f(0.0, 0.0, 0.0, 0.5));
	let t: vec4f = (m * v.pos) + (m[3] * 0.0);
	let t_2: f32 = v.pos.w;
	return BuiltinVaryings(t, t_2, v.pos.xy);
}
struct StageOut {
	@builtin(position) pos: vec4f,
	@location(0) a: f32,
	@location(1) b: vec2f,
}
@vertex fn main(@location(0) in_pos: vec4f) -> StageOut {
	let r = vs(BuiltinVertex(in_pos));
	return StageOut(r.pos, r.a, r.b);
}
