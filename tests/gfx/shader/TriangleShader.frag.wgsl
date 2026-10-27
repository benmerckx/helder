struct Varyings {
	pos: vec4f,
	color: vec3f,
}
fn fs(i: Varyings) -> vec4f {
	return vec4f(i.color, 1.0);
}
@fragment fn main(@builtin(position) in_pos: vec4f, @location(0) in_color: vec3f) -> @location(0) vec4f {
	return fs(Varyings(in_pos, in_color));
}
