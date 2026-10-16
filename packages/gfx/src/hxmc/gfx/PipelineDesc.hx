package hxmc.gfx;

typedef PipelineDesc = {
	vertex:Shader,
	fragment:Shader,
	layout:Array<VertexBufferLayout>,
	?topology:Topology,
	?cull:Cull
}
