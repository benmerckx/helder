package hxmc.gfx;

typedef PipelineDesc = {
	// the stages' shaders, or instead their code (a shader class's
	// pipeline(): Device.createPipeline compiles it)
	?vertex:Shader,
	?fragment:Shader,
	?program:{vertex:ShaderCode, fragment:ShaderCode},
	layout:Array<VertexBufferLayout>,
	?topology:Topology,
	?cull:Cull
}
