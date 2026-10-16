package hxmc.gfx;

// The shader's source for each kind of back end: emitted by the shader
// macro (hxmc.gfx.shader: a Shaders class's vertexCode and fragmentCode,
// in the target's languages only), or written by hand. GL (also on
// WebGL2): GLSL ES 3.00 (`#version 300 es`), vertex inputs at
// `layout(location = n)`. Metal: MSL, the entry point named main0 (as
// SPIRV-Cross names it), vertex inputs `[[attribute(n)]]` of a
// `[[stage_in]]` struct. D3D11: HLSL (shader model 5.0, or 4.0 on older
// devices), the entry point named main, vertex inputs at semantic
// `TEXCOORD<n>` (as SPIRV-Cross names them). WebGPU: WGSL, the entry point
// named main, vertex inputs at `@location(n)`.
typedef ShaderCode = {
	?glsl:String,
	?msl:String,
	?hlsl:String,
	?wgsl:String
}
