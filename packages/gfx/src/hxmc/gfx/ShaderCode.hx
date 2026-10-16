package hxmc.gfx;

// The shader's source for each kind of back end: written by hand for now,
// emitted by the shader macro later (which also gives the vertex layout and
// the uniform slots). GL: GLSL ES 3.00 (`#version 300 es`), vertex inputs
// at `layout(location = n)`.
typedef ShaderCode = {
	?glsl:String
}
