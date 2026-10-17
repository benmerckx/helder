struct InstanceVaryings {
	pos: vec4f,
	color: vec3f,
	corner: vec2f,
}
fn fs(i: InstanceVaryings) -> vec4f {
	return vec4f(i.color * (1.0 - (0.3 * length(i.corner))), 1.0);
}
@fragment fn main(@builtin(position) in_pos: vec4f, @location(0) in_color: vec3f, @location(1) in_corner: vec2f) -> @location(0) vec4f {
	return fs(InstanceVaryings(in_pos, in_color, in_corner));
}
