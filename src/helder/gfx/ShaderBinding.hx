package helder.gfx;

// A resource a shader reads at a slot, set at draw time (Encoder.setUniforms,
// setTexture): name is the GLSL's (a uniform block's or a sampler2D's), since
// GLSL ES 3.00 has no layout(binding) and the GL back end binds them by name
// (glUniformBlockBinding, glUniform1i); WebGPU makes its bind group layout of
// the kinds. The shader macro lists them in ShaderCode.bindings.
typedef ShaderBinding = {
	name:String,
	slot:Int,
	kind:BindingKind,
	// a uniform block's size in bytes (std140)
	?size:Int
}

enum abstract BindingKind(Int) {
	var Uniform;
	// a texture and its sampler
	var Texture;
}
