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

	// the indices of drawIndexed, from offset bytes into b
	public inline function setIndexBuffer(b:Buffer, format:IndexFormat, offset = 0)
		impl.setIndexBuffer(b.id(), format, offset);

	// a uniform block's contents for the next draws, at its slot (a shader
	// class's uniforms: binding; its write<Block> fills the bytes): size bytes
	// of data from offset (default: the rest), copied into the frame's
	// uniform ring (at most UNIFORM_RING bytes a frame, each block 256-byte
	// aligned; Metal: at most 4 KB a block)
	public inline function setUniforms(slot:Int, data:haxe.io.Bytes, offset = 0, size = -1)
		impl.setUniforms(slot, data, offset, size < 0 ? data.length - offset : size);

	public inline function draw(vertices:Int, instances = 1, firstVertex = 0)
		impl.draw(vertices, instances, firstVertex);

	// count indices of the index buffer from firstIndex, each plus baseVertex
	public inline function drawIndexed(count:Int, instances = 1, firstIndex = 0, baseVertex = 0)
		impl.drawIndexed(count, instances, firstIndex, baseVertex);

	public inline function endPass()
		impl.endPass();

	// the uniform ring's size per frame in flight
	public static inline var UNIFORM_RING = 256 * 1024;
}
