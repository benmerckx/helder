package helder.gfx.shader;

// a value the CPU sets and the shaders that read it get (ShaderMath.uniform,
// a module-level final; uniform.value in a stage: a field of the shader's
// generated block, Shader.uniformBytes). @:generic: its value held as its
// own type (a vector a value of its own, set as a whole: u.value = v).
@:generic class Uniform<T> {
	public var value:T;

	public function new(value:T)
		this.value = value;
}
