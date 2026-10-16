package hxmc.gfx;

// Records a frame's passes: one per device, reused (no allocation per frame).
final class Encoder {
	final impl:Impl;

	@:allow(hxmc.gfx.Device) function new(impl:Impl)
		this.impl = impl;

	public inline function beginPass(p:PassDesc)
		impl.beginPass(p);

	public inline function setPipeline(p:Pipeline)
		impl.setPipeline(p.id());

	public inline function setVertexBuffer(slot:Int, b:Buffer, offset = 0)
		impl.setVertexBuffer(slot, b.id(), offset);

	public inline function draw(vertices:Int, instances = 1, firstVertex = 0)
		impl.draw(vertices, instances, firstVertex);

	public inline function endPass()
		impl.endPass();
}
