package helder.gfx;

// how a vertex buffer's elements advance: one per vertex, or one per
// instance (every vertex of an instance reads the same element)
enum abstract VertexStep(Int) {
	var Vertex;
	var Instance;
}
