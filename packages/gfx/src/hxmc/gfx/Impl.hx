package hxmc.gfx;

import hxmc.gfx.gl.GLBackend;
import hxmc.gfx.metal.MetalBackend;
import hxmc.os.Surface;
import hxmc.unsafe.Mem;

// The back end of this target: Metal on macOS, GL elsewhere (D3D11 and
// WebGL2 come in here). Mem.os() is known when compiling, so each call
// reaches one back end's code only (and imports only its libraries): no
// field has a back end's type, which would compile all its methods.
abstract Impl(Any) {
	public inline function new(surface:Surface)
		this = Mem.os() == 1 ? new MetalBackend(surface) : new GLBackend(surface);

	inline function mtl():MetalBackend
		return cast this;

	inline function gl():GLBackend
		return cast this;

	public var backend(get, never):Backend;
	public var width(get, never):Int;
	public var height(get, never):Int;

	inline function get_backend()
		return Mem.os() == 1 ? mtl().backend : gl().backend;

	inline function get_width()
		return Mem.os() == 1 ? mtl().width : gl().width;

	inline function get_height()
		return Mem.os() == 1 ? mtl().height : gl().height;

	public inline function createBuffer(d:BufferDesc):Int
		return Mem.os() == 1 ? mtl().createBuffer(d) : gl().createBuffer(d);

	public inline function createShader(d:ShaderDesc):Int
		return Mem.os() == 1 ? mtl().createShader(d) : gl().createShader(d);

	public inline function createPipeline(d:PipelineDesc):Int
		return Mem.os() == 1 ? mtl().createPipeline(d) : gl().createPipeline(d);

	public inline function beginFrame():Bool
		return Mem.os() == 1 ? mtl().beginFrame() : gl().beginFrame();

	public inline function beginPass(p:PassDesc)
		Mem.os() == 1 ? mtl().beginPass(p) : gl().beginPass(p);

	public inline function setPipeline(id:Int)
		Mem.os() == 1 ? mtl().setPipeline(id) : gl().setPipeline(id);

	public inline function setVertexBuffer(slot:Int, id:Int, offset:Int)
		Mem.os() == 1 ? mtl().setVertexBuffer(slot, id, offset) : gl().setVertexBuffer(slot, id, offset);

	public inline function draw(vertices:Int, instances:Int, first:Int)
		Mem.os() == 1 ? mtl().draw(vertices, instances, first) : gl().draw(vertices, instances, first);

	public inline function endPass()
		Mem.os() == 1 ? mtl().endPass() : gl().endPass();

	public inline function endFrame()
		Mem.os() == 1 ? mtl().endFrame() : gl().endFrame();

	public inline function readPixels(dst:haxe.io.Bytes)
		Mem.os() == 1 ? mtl().readPixels(dst) : gl().readPixels(dst);

	public inline function dispose()
		Mem.os() == 1 ? mtl().dispose() : gl().dispose();
}
