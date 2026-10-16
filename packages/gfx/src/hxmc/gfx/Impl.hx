package hxmc.gfx;

import hxmc.gfx.d3d11.D3D11Backend;
import hxmc.gfx.gl.GLBackend;
import hxmc.gfx.metal.MetalBackend;
import hxmc.gfx.webgpu.WebGPUBackend;
import hxmc.os.Surface;
import hxmc.unsafe.Mem;

// The back end of this target: Metal on macOS, D3D11 on Windows, WebGPU in
// the browser (WebAssembly), GL elsewhere. Mem.os() is known when compiling,
// so each call reaches one back end's code only (and imports only its
// libraries): no field has a back end's type, which would compile all its
// methods.
abstract Impl(Any) {
	public inline function new(surface:Surface)
		this = Mem.os() == 1 ? new MetalBackend(surface) : Mem.os() == 2 ? new D3D11Backend(surface) : Mem.os() == 3 ? new WebGPUBackend(surface) : new GLBackend(surface);

	inline function mtl():MetalBackend
		return cast this;

	inline function d3d():D3D11Backend
		return cast this;

	inline function gl():GLBackend
		return cast this;

	inline function wgpu():WebGPUBackend
		return cast this;

	public var backend(get, never):Backend;
	public var width(get, never):Int;
	public var height(get, never):Int;

	inline function get_backend()
		return Mem.os() == 1 ? mtl().backend : Mem.os() == 2 ? d3d().backend : Mem.os() == 3 ? wgpu().backend : gl().backend;

	inline function get_width()
		return Mem.os() == 1 ? mtl().width : Mem.os() == 2 ? d3d().width : Mem.os() == 3 ? wgpu().width : gl().width;

	inline function get_height()
		return Mem.os() == 1 ? mtl().height : Mem.os() == 2 ? d3d().height : Mem.os() == 3 ? wgpu().height : gl().height;

	public inline function createBuffer(d:BufferDesc):Int
		return Mem.os() == 1 ? mtl().createBuffer(d) : Mem.os() == 2 ? d3d().createBuffer(d) : Mem.os() == 3 ? wgpu().createBuffer(d) : gl().createBuffer(d);

	public inline function createShader(d:ShaderDesc):Int
		return Mem.os() == 1 ? mtl().createShader(d) : Mem.os() == 2 ? d3d().createShader(d) : Mem.os() == 3 ? wgpu().createShader(d) : gl().createShader(d);

	public inline function createPipeline(d:PipelineDesc):Int
		return Mem.os() == 1 ? mtl().createPipeline(d) : Mem.os() == 2 ? d3d().createPipeline(d) : Mem.os() == 3 ? wgpu().createPipeline(d) : gl().createPipeline(d);

	public inline function beginFrame():Bool
		return Mem.os() == 1 ? mtl().beginFrame() : Mem.os() == 2 ? d3d().beginFrame() : Mem.os() == 3 ? wgpu().beginFrame() : gl().beginFrame();

	public inline function beginPass(p:PassDesc)
		Mem.os() == 1 ? mtl().beginPass(p) : Mem.os() == 2 ? d3d().beginPass(p) : Mem.os() == 3 ? wgpu().beginPass(p) : gl().beginPass(p);

	public inline function setPipeline(id:Int)
		Mem.os() == 1 ? mtl().setPipeline(id) : Mem.os() == 2 ? d3d().setPipeline(id) : Mem.os() == 3 ? wgpu().setPipeline(id) : gl().setPipeline(id);

	public inline function setVertexBuffer(slot:Int, id:Int, offset:Int)
		Mem.os() == 1 ? mtl().setVertexBuffer(slot, id, offset) : Mem.os() == 2 ? d3d().setVertexBuffer(slot, id, offset) : Mem.os() == 3 ? wgpu()
			.setVertexBuffer(slot, id, offset) : gl().setVertexBuffer(slot, id, offset);

	public inline function draw(vertices:Int, instances:Int, first:Int)
		Mem.os() == 1 ? mtl().draw(vertices, instances, first) : Mem.os() == 2 ? d3d().draw(vertices, instances, first) : Mem.os() == 3 ? wgpu()
			.draw(vertices, instances, first) : gl().draw(vertices, instances, first);

	public inline function endPass()
		Mem.os() == 1 ? mtl().endPass() : Mem.os() == 2 ? d3d().endPass() : Mem.os() == 3 ? wgpu().endPass() : gl().endPass();

	public inline function endFrame()
		Mem.os() == 1 ? mtl().endFrame() : Mem.os() == 2 ? d3d().endFrame() : Mem.os() == 3 ? wgpu().endFrame() : gl().endFrame();

	public inline function readPixels(dst:haxe.io.Bytes)
		Mem.os() == 1 ? mtl().readPixels(dst) : Mem.os() == 2 ? d3d().readPixels(dst) : Mem.os() == 3 ? wgpu().readPixels(dst) : gl().readPixels(dst);

	public inline function dispose()
		Mem.os() == 1 ? mtl().dispose() : Mem.os() == 2 ? d3d().dispose() : Mem.os() == 3 ? wgpu().dispose() : gl().dispose();
}
