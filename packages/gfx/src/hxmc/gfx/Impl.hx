package hxmc.gfx;

import hxmc.gfx.d3d11.D3D11Backend;
import hxmc.gfx.gl.GLBackend;
import hxmc.gfx.metal.MetalBackend;
import hxmc.gfx.webgpu.WebGPU;
import hxmc.gfx.webgpu.WebGPUBackend;
import hxmc.os.Surface;
import hxmc.unsafe.Mem;

// The back end of this target: Metal on macOS, D3D11 on Windows, GL
// elsewhere; in the browser (WebAssembly), WebGPU when the JavaScript side
// has a device (requested before main: WebGPU.ready), else GL on WebGL2.
// Mem.os() is known when compiling, so each call reaches one back end's
// code only (and imports only its libraries), or in the browser one of
// those two, told apart by the object's class: no field has a back end's
// type, which would compile all its methods.
abstract Impl(Any) {
	public inline function new(surface:Surface)
		this = Mem.os() == 1 ? new MetalBackend(surface) : Mem.os() == 2 ? new D3D11Backend(surface) : Mem.os() != 3 ? new GLBackend(surface) : WebGPU.ready() != 0 ? new WebGPUBackend(surface) : new GLBackend(surface);

	// (the browser: WebGL2's)
	inline function webgl():Bool
		return Std.isOfType(this, GLBackend);

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
		return Mem.os() == 1 ? mtl().backend : Mem.os() == 2 ? d3d().backend : Mem.os() != 3 ? gl().backend : webgl() ? gl().backend : wgpu().backend;

	inline function get_width()
		return Mem.os() == 1 ? mtl().width : Mem.os() == 2 ? d3d().width : Mem.os() != 3 ? gl().width : webgl() ? gl().width : wgpu().width;

	inline function get_height()
		return Mem.os() == 1 ? mtl().height : Mem.os() == 2 ? d3d().height : Mem.os() != 3 ? gl().height : webgl() ? gl().height : wgpu().height;

	public inline function createBuffer(d:BufferDesc):Int
		return Mem.os() == 1 ? mtl().createBuffer(d) : Mem.os() == 2 ? d3d().createBuffer(d) : Mem.os() != 3 ? gl().createBuffer(d) : webgl() ? gl().createBuffer(d) : wgpu().createBuffer(d);

	public inline function writeBuffer(id:Int, offset:Int, data:haxe.io.Bytes, dataOffset:Int, size:Int)
		Mem.os() == 1 ? mtl().writeBuffer(id, offset, data, dataOffset, size) : Mem.os() == 2 ? d3d().writeBuffer(id, offset, data, dataOffset, size) : Mem.os() != 3 ? gl().writeBuffer(id, offset, data, dataOffset, size) : webgl() ? gl().writeBuffer(id, offset, data, dataOffset, size) : wgpu().writeBuffer(id, offset, data, dataOffset, size);

	public inline function createTexture(d:TextureDesc):Int
		return Mem.os() == 1 ? mtl().createTexture(d) : Mem.os() == 2 ? d3d().createTexture(d) : Mem.os() != 3 ? gl().createTexture(d) : webgl() ? gl().createTexture(d) : wgpu().createTexture(d);

	public inline function writeTexture(id:Int, data:haxe.io.Bytes, x:Int, y:Int, w:Int, h:Int, dataOffset:Int, level:Int)
		Mem.os() == 1 ? mtl().writeTexture(id, data, x, y, w, h, dataOffset, level) : Mem.os() == 2 ? d3d().writeTexture(id, data, x, y, w, h, dataOffset,
			level) : Mem.os() != 3 ? gl().writeTexture(id, data, x, y, w, h, dataOffset, level) : webgl() ? gl().writeTexture(id, data, x, y, w, h,
			dataOffset, level) : wgpu().writeTexture(id, data, x, y, w, h, dataOffset, level);

	public inline function generateMips(id:Int)
		Mem.os() == 1 ? mtl().generateMips(id) : Mem.os() == 2 ? d3d().generateMips(id) : Mem.os() != 3 ? gl().generateMips(id) : webgl() ? gl().generateMips(id) : wgpu().generateMips(id);

	public inline function destroyBuffer(id:Int)
		Mem.os() == 1 ? mtl().destroyBuffer(id) : Mem.os() == 2 ? d3d().destroyBuffer(id) : Mem.os() != 3 ? gl().destroyBuffer(id) : webgl() ? gl().destroyBuffer(id) : wgpu().destroyBuffer(id);

	public inline function destroyTexture(id:Int)
		Mem.os() == 1 ? mtl().destroyTexture(id) : Mem.os() == 2 ? d3d().destroyTexture(id) : Mem.os() != 3 ? gl().destroyTexture(id) : webgl() ? gl().destroyTexture(id) : wgpu().destroyTexture(id);

	public inline function createSampler(d:SamplerDesc):Int
		return Mem.os() == 1 ? mtl().createSampler(d) : Mem.os() == 2 ? d3d().createSampler(d) : Mem.os() != 3 ? gl().createSampler(d) : webgl() ? gl().createSampler(d) : wgpu().createSampler(d);

	public inline function createShader(d:ShaderDesc):Int
		return Mem.os() == 1 ? mtl().createShader(d) : Mem.os() == 2 ? d3d().createShader(d) : Mem.os() != 3 ? gl().createShader(d) : webgl() ? gl().createShader(d) : wgpu().createShader(d);

	public inline function createPipeline(d:PipelineDesc):Int
		return Mem.os() == 1 ? mtl().createPipeline(d) : Mem.os() == 2 ? d3d().createPipeline(d) : Mem.os() != 3 ? gl().createPipeline(d) : webgl() ? gl().createPipeline(d) : wgpu().createPipeline(d);

	public inline function beginFrame():Bool
		return Mem.os() == 1 ? mtl().beginFrame() : Mem.os() == 2 ? d3d().beginFrame() : Mem.os() != 3 ? gl().beginFrame() : webgl() ? gl().beginFrame() : wgpu().beginFrame();

	public inline function beginPass(p:PassDesc)
		Mem.os() == 1 ? mtl().beginPass(p) : Mem.os() == 2 ? d3d().beginPass(p) : Mem.os() != 3 ? gl().beginPass(p) : webgl() ? gl().beginPass(p) : wgpu().beginPass(p);

	public inline function setPipeline(id:Int)
		Mem.os() == 1 ? mtl().setPipeline(id) : Mem.os() == 2 ? d3d().setPipeline(id) : Mem.os() != 3 ? gl().setPipeline(id) : webgl() ? gl().setPipeline(id) : wgpu().setPipeline(id);

	public inline function setVertexBuffer(slot:Int, id:Int, offset:Int)
		Mem.os() == 1 ? mtl().setVertexBuffer(slot, id, offset) : Mem.os() == 2 ? d3d().setVertexBuffer(slot, id, offset) : Mem.os() != 3 ? gl().setVertexBuffer(slot, id, offset) : webgl() ? gl().setVertexBuffer(slot, id, offset) : wgpu().setVertexBuffer(slot, id, offset);

	public inline function setIndexBuffer(id:Int, format:IndexFormat, offset:Int)
		Mem.os() == 1 ? mtl().setIndexBuffer(id, format, offset) : Mem.os() == 2 ? d3d().setIndexBuffer(id, format, offset) : Mem.os() != 3 ? gl().setIndexBuffer(id, format, offset) : webgl() ? gl().setIndexBuffer(id, format, offset) : wgpu().setIndexBuffer(id, format, offset);

	public inline function setUniforms(slot:Int, data:haxe.io.Bytes, offset:Int, size:Int)
		Mem.os() == 1 ? mtl().setUniforms(slot, data, offset, size) : Mem.os() == 2 ? d3d().setUniforms(slot, data, offset, size) : Mem.os() != 3 ? gl().setUniforms(slot, data, offset, size) : webgl() ? gl().setUniforms(slot, data, offset, size) : wgpu().setUniforms(slot, data, offset, size);

	public inline function setTexture(slot:Int, texture:Int, sampler:Int)
		Mem.os() == 1 ? mtl().setTexture(slot, texture, sampler) : Mem.os() == 2 ? d3d().setTexture(slot, texture, sampler) : Mem.os() != 3 ? gl().setTexture(slot, texture, sampler) : webgl() ? gl().setTexture(slot, texture, sampler) : wgpu().setTexture(slot, texture, sampler);

	public inline function draw(vertices:Int, instances:Int, first:Int)
		Mem.os() == 1 ? mtl().draw(vertices, instances, first) : Mem.os() == 2 ? d3d().draw(vertices, instances, first) : Mem.os() != 3 ? gl().draw(vertices, instances, first) : webgl() ? gl().draw(vertices, instances, first) : wgpu().draw(vertices, instances, first);

	public inline function drawIndexed(count:Int, instances:Int, first:Int, baseVertex:Int)
		Mem.os() == 1 ? mtl().drawIndexed(count, instances, first, baseVertex) : Mem.os() == 2 ? d3d().drawIndexed(count, instances, first, baseVertex) : Mem.os() != 3 ? gl().drawIndexed(count, instances, first, baseVertex) : webgl() ? gl().drawIndexed(count, instances, first, baseVertex) : wgpu().drawIndexed(count, instances, first, baseVertex);

	public inline function endPass()
		Mem.os() == 1 ? mtl().endPass() : Mem.os() == 2 ? d3d().endPass() : Mem.os() != 3 ? gl().endPass() : webgl() ? gl().endPass() : wgpu().endPass();

	public inline function endFrame()
		Mem.os() == 1 ? mtl().endFrame() : Mem.os() == 2 ? d3d().endFrame() : Mem.os() != 3 ? gl().endFrame() : webgl() ? gl().endFrame() : wgpu().endFrame();

	public inline function readPixels(dst:haxe.io.Bytes)
		Mem.os() == 1 ? mtl().readPixels(dst) : Mem.os() == 2 ? d3d().readPixels(dst) : Mem.os() != 3 ? gl().readPixels(dst) : webgl() ? gl().readPixels(dst) : wgpu().readPixels(dst);

	public inline function dispose()
		Mem.os() == 1 ? mtl().dispose() : Mem.os() == 2 ? d3d().dispose() : Mem.os() != 3 ? gl().dispose() : webgl() ? gl().dispose() : wgpu().dispose();
}
