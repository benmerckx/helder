package hxmc.gfx;

// The shader's source for each kind of back end: written by hand for now,
// emitted by the shader macro later (which also gives the vertex layout and
// the uniform slots). GL: GLSL ES 3.00 (`#version 300 es`), vertex inputs
// at `layout(location = n)`. Metal: MSL, the entry point named main0 (as
// SPIRV-Cross names it), vertex inputs `[[attribute(n)]]` of a
// `[[stage_in]]` struct. D3D11: HLSL (shader model 5.0, or 4.0 on older
// devices), the entry point named main, vertex inputs at semantic
// `TEXCOORD<n>` (as SPIRV-Cross names them).
typedef ShaderCode = {
	?glsl:String,
	?msl:String,
	?hlsl:String
}
