package hxmc.gfx;

typedef PipelineDesc = {
	// the stages' shaders, or instead their code (a shader class's
	// pipeline(): Device.createPipeline compiles it)
	?vertex:Shader,
	?fragment:Shader,
	?program:{vertex:ShaderCode, fragment:ShaderCode},
	layout:Array<VertexBufferLayout>,
	?topology:Topology,
	?cull:Cull,
	?blend:Blend,
	// the depth test (default Always: none) and whether fragments that pass
	// it write their depth (default false)
	?depthCompare:Compare,
	?depthWrite:Bool
}
