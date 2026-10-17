struct InstanceVertex {
	corner: vec2f,
	at: vec2f,
	size: f32,
	angle: f32,
	color: vec3f,
}
struct InstanceField {
	scale: vec2f,
	time: f32,
}
struct InstanceVaryings {
	pos: vec4f,
	color: vec3f,
	corner: vec2f,
}
fn vs(v: InstanceVertex, f: InstanceField) -> InstanceVaryings {
	let a: f32 = v.angle + f.time;
	let c: f32 = cos(a);
	let s: f32 = sin(a);
	let p: vec2f = (vec2f((v.corner.x * c) - (v.corner.y * s), (v.corner.x * s) + (v.corner.y * c)) * v.size) + v.at;
	return InstanceVaryings(vec4f(p * f.scale, 0.0, 1.0), v.color, v.corner);
}
@group(0) @binding(0) var<uniform> u_0: InstanceField;
struct StageOut {
	@builtin(position) pos: vec4f,
	@location(0) color: vec3f,
	@location(1) corner: vec2f,
}
@vertex fn main(@location(0) in_corner: vec2f, @location(1) in_at: vec2f, @location(2) in_size: f32, @location(3) in_angle: f32, @location(4) in_color: vec3f) -> StageOut {
	let r = vs(InstanceVertex(in_corner, in_at, in_size, in_angle, in_color), u_0);
	return StageOut(r.pos, r.color, r.corner);
}
