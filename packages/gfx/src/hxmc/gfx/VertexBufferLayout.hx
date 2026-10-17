package hxmc.gfx;

// one vertex buffer slot (setVertexBuffer's slot is the index in the layout);
// step: Vertex (the default) or Instance (drawIndexed's baseVertex does not
// move an instance buffer)
typedef VertexBufferLayout = {
	stride:Int,
	attributes:Array<VertexAttribute>,
	?step:VertexStep
}
