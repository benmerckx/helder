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

	// the fragment stage's texture at a slot (its sampler is the texture's filter)
	public inline function setTexture(slot:Int, t:Texture)
		impl.setTexture(slot, t.id());

	// draws only inside this rectangle of the target, in pixels from the top
	// left (clamped to the target); each pass starts with the whole target
	public inline function setScissor(x:Int, y:Int, width:Int, height:Int)
		impl.setScissor(x, y, width, height);

	public inline function draw(vertices:Int, instances = 1, firstVertex = 0)
		impl.draw(vertices, instances, firstVertex);

	public inline function endPass()
		impl.endPass();
}
