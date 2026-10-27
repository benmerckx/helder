struct LitVertex {
	pos: vec3f,
	normal: vec3f,
	uv: vec2f,
}
struct Camera {
	viewProj: mat4x4f,
	eye: vec3f,
	time: f32,
}
struct LitVaryings {
	normal: vec3f,
	clip: vec4f,
	uv: vec2f,
	shade: f32,
}
fn lambert(n: vec3f, l: vec3f) -> f32 {
	return max(dot(normalize(n), normalize(l)), 0.0);
}
fn vs(v: LitVertex, cam: Camera) -> LitVaryings {
	let clip: vec4f = cam.viewProj * vec4f(v.pos, 1.0);
	let wobble: f32 = sin(cam.time + (v.pos.x * 3.0)) * 0.05;
	let t: vec3f = v.normal;
	let t_2: vec4f = clip + vec4f(wobble, 0.0, 0.0, 0.0);
	let t_3: vec2f = v.uv.yx;
	return LitVaryings(t, t_2, t_3, lambert(v.normal, cam.eye - v.pos));
}
@group(0) @binding(0) var<uniform> u_0: Camera;
struct StageOut {
	@builtin(position) clip: vec4f,
	@location(0) normal: vec3f,
	@location(1) uv: vec2f,
	@location(2) shade: f32,
}
@vertex fn main(@location(0) in_pos: vec3f, @location(1) in_normal: vec3f, @location(2) in_uv: vec2f) -> StageOut {
	let r = vs(LitVertex(in_pos, in_normal, in_uv), u_0);
	return StageOut(r.clip, r.normal, r.uv, r.shade);
}
