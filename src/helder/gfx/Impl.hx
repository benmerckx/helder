package helder.gfx;

import helder.gfx.d3d11.D3D11Backend;
import helder.gfx.gl.GLBackend;
import helder.gfx.metal.MetalBackend;
import helder.gfx.webgpu.WebGPU;
import helder.gfx.webgpu.WebGPUBackend;
import helder.os.Surface;
import hxmc.Platform;

// The back end of this target: Metal on macOS, D3D11 on Windows, GL
// elsewhere; in the browser (WebAssembly), WebGPU when the JavaScript side
// has a device (requested before main: WebGPU.ready), else GL on WebGL2.
// Platform.os() is known when compiling, so each call reaches one back end's
// code only (and imports only its libraries), or in the browser one of
// those two, told apart by the object's class: no field has a back end's
// type, which would compile all its methods.
abstract Impl(Any) {
	// (antialias: every back end's; in the browser the page's run option antialias, when set, decides)
	public inline function new(surface:Surface, antialias:Bool)
		this = Platform.os() == 1 ? new MetalBackend(surface, antialias) : Platform.os() == 2 ? new D3D11Backend(surface, antialias) : Platform.os() != 3 ? new GLBackend(surface,
			antialias) : WebGPU.ready() != 0 ? new WebGPUBackend(surface, antialias) : new GLBackend(surface, antialias);

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
		return Platform.os() == 1 ? mtl().backend : Platform.os() == 2 ? d3d().backend : Platform.os() != 3 ? gl().backend : webgl() ? gl().backend : wgpu().backend;

	inline function get_width()
		return Platform.os() == 1 ? mtl().width : Platform.os() == 2 ? d3d().width : Platform.os() != 3 ? gl().width : webgl() ? gl().width : wgpu().width;

	inline function get_height()
		return Platform.os() == 1 ? mtl().height : Platform.os() == 2 ? d3d().height : Platform.os() != 3 ? gl().height : webgl() ? gl().height : wgpu().height;

	public inline function createBuffer(d:BufferDesc):Int
		return Platform.os() == 1 ? mtl().createBuffer(d) : Platform.os() == 2 ? d3d().createBuffer(d) : Platform.os() != 3 ? gl().createBuffer(d) : webgl() ? gl().createBuffer(d) : wgpu().createBuffer(d);

	public inline function writeBuffer(id:Int, offset:Int, data:haxe.io.Bytes, dataOffset:Int, size:Int)
		Platform.os() == 1 ? mtl().writeBuffer(id, offset, data, dataOffset, size) : Platform.os() == 2 ? d3d().writeBuffer(id, offset, data, dataOffset, size) : Platform.os() != 3 ? gl().writeBuffer(id, offset, data, dataOffset, size) : webgl() ? gl().writeBuffer(id, offset, data, dataOffset, size) : wgpu().writeBuffer(id, offset, data, dataOffset, size);

	public inline function createTexture(d:TextureDesc):Int
		return Platform.os() == 1 ? mtl().createTexture(d) : Platform.os() == 2 ? d3d().createTexture(d) : Platform.os() != 3 ? gl().createTexture(d) : webgl() ? gl().createTexture(d) : wgpu().createTexture(d);

	public inline function writeTexture(id:Int, data:haxe.io.Bytes, x:Int, y:Int, w:Int, h:Int, dataOffset:Int, level:Int)
		Platform.os() == 1 ? mtl().writeTexture(id, data, x, y, w, h, dataOffset, level) : Platform.os() == 2 ? d3d().writeTexture(id, data, x, y, w, h, dataOffset,
			level) : Platform.os() != 3 ? gl().writeTexture(id, data, x, y, w, h, dataOffset, level) : webgl() ? gl().writeTexture(id, data, x, y, w, h,
			dataOffset, level) : wgpu().writeTexture(id, data, x, y, w, h, dataOffset, level);

	// (the browser's: WebGPU's or WebGL2's)
	public inline function writeTextureImage(id:Int, image:Int, release:Bool)
		Platform.os() != 3 ? throw "helder.gfx: writeTextureImage: in a browser only" : webgl() ? gl().writeTextureImage(id, image, release) : wgpu().writeTextureImage(id, image, release);

	public inline function supports(f:TextureFormat):Bool
		return Platform.os() == 1 ? mtl().supports(f) : Platform.os() == 2 ? d3d().supports(f) : Platform.os() != 3 ? gl().supports(f) : webgl() ? gl().supports(f) : wgpu().supports(f);

	public inline function maxTextureSize():Int
		return Platform.os() == 1 || Platform.os() == 2 ? 16384 : Platform.os() != 3 || webgl() ? gl().maxTextureSize() : wgpu().maxTextureSize();

	public inline function generateMips(id:Int)
		Platform.os() == 1 ? mtl().generateMips(id) : Platform.os() == 2 ? d3d().generateMips(id) : Platform.os() != 3 ? gl().generateMips(id) : webgl() ? gl().generateMips(id) : wgpu().generateMips(id);

	public inline function destroyBuffer(id:Int)
		Platform.os() == 1 ? mtl().destroyBuffer(id) : Platform.os() == 2 ? d3d().destroyBuffer(id) : Platform.os() != 3 ? gl().destroyBuffer(id) : webgl() ? gl().destroyBuffer(id) : wgpu().destroyBuffer(id);

	public inline function destroyTexture(id:Int)
		Platform.os() == 1 ? mtl().destroyTexture(id) : Platform.os() == 2 ? d3d().destroyTexture(id) : Platform.os() != 3 ? gl().destroyTexture(id) : webgl() ? gl().destroyTexture(id) : wgpu().destroyTexture(id);

	public inline function createSampler(d:SamplerDesc):Int
		return Platform.os() == 1 ? mtl().createSampler(d) : Platform.os() == 2 ? d3d().createSampler(d) : Platform.os() != 3 ? gl().createSampler(d) : webgl() ? gl().createSampler(d) : wgpu().createSampler(d);

	public inline function createShader(d:ShaderDesc):Int
		return Platform.os() == 1 ? mtl().createShader(d) : Platform.os() == 2 ? d3d().createShader(d) : Platform.os() != 3 ? gl().createShader(d) : webgl() ? gl().createShader(d) : wgpu().createShader(d);

	public inline function createPipeline(d:PipelineDesc):Int
		return Platform.os() == 1 ? mtl().createPipeline(d) : Platform.os() == 2 ? d3d().createPipeline(d) : Platform.os() != 3 ? gl().createPipeline(d) : webgl() ? gl().createPipeline(d) : wgpu().createPipeline(d);

	public inline function beginFrame():Bool
		return Platform.os() == 1 ? mtl().beginFrame() : Platform.os() == 2 ? d3d().beginFrame() : Platform.os() != 3 ? gl().beginFrame() : webgl() ? gl().beginFrame() : wgpu().beginFrame();

	public inline function beginPass(p:PassDesc)
		Platform.os() == 1 ? mtl().beginPass(p) : Platform.os() == 2 ? d3d().beginPass(p) : Platform.os() != 3 ? gl().beginPass(p) : webgl() ? gl().beginPass(p) : wgpu().beginPass(p);

	public inline function setPipeline(id:Int)
		Platform.os() == 1 ? mtl().setPipeline(id) : Platform.os() == 2 ? d3d().setPipeline(id) : Platform.os() != 3 ? gl().setPipeline(id) : webgl() ? gl().setPipeline(id) : wgpu().setPipeline(id);

	public inline function setVertexBuffer(slot:Int, id:Int, offset:Int)
		Platform.os() == 1 ? mtl().setVertexBuffer(slot, id, offset) : Platform.os() == 2 ? d3d().setVertexBuffer(slot, id, offset) : Platform.os() != 3 ? gl().setVertexBuffer(slot, id, offset) : webgl() ? gl().setVertexBuffer(slot, id, offset) : wgpu().setVertexBuffer(slot, id, offset);

	public inline function setIndexBuffer(id:Int, format:IndexFormat, offset:Int)
		Platform.os() == 1 ? mtl().setIndexBuffer(id, format, offset) : Platform.os() == 2 ? d3d().setIndexBuffer(id, format, offset) : Platform.os() != 3 ? gl().setIndexBuffer(id, format, offset) : webgl() ? gl().setIndexBuffer(id, format, offset) : wgpu().setIndexBuffer(id, format, offset);

	public inline function setUniforms(slot:Int, data:haxe.io.Bytes, offset:Int, size:Int)
		Platform.os() == 1 ? mtl().setUniforms(slot, data, offset, size) : Platform.os() == 2 ? d3d().setUniforms(slot, data, offset, size) : Platform.os() != 3 ? gl().setUniforms(slot, data, offset, size) : webgl() ? gl().setUniforms(slot, data, offset, size) : wgpu().setUniforms(slot, data, offset, size);

	public inline function setTexture(slot:Int, texture:Int, sampler:Int)
		Platform.os() == 1 ? mtl().setTexture(slot, texture, sampler) : Platform.os() == 2 ? d3d().setTexture(slot, texture, sampler) : Platform.os() != 3 ? gl().setTexture(slot, texture, sampler) : webgl() ? gl().setTexture(slot, texture, sampler) : wgpu().setTexture(slot, texture, sampler);

	public inline function draw(vertices:Int, instances:Int, first:Int)
		Platform.os() == 1 ? mtl().draw(vertices, instances, first) : Platform.os() == 2 ? d3d().draw(vertices, instances, first) : Platform.os() != 3 ? gl().draw(vertices, instances, first) : webgl() ? gl().draw(vertices, instances, first) : wgpu().draw(vertices, instances, first);

	public inline function drawIndexed(count:Int, instances:Int, first:Int, baseVertex:Int)
		Platform.os() == 1 ? mtl().drawIndexed(count, instances, first, baseVertex) : Platform.os() == 2 ? d3d().drawIndexed(count, instances, first, baseVertex) : Platform.os() != 3 ? gl().drawIndexed(count, instances, first, baseVertex) : webgl() ? gl().drawIndexed(count, instances, first, baseVertex) : wgpu().drawIndexed(count, instances, first, baseVertex);

	public inline function endPass()
		Platform.os() == 1 ? mtl().endPass() : Platform.os() == 2 ? d3d().endPass() : Platform.os() != 3 ? gl().endPass() : webgl() ? gl().endPass() : wgpu().endPass();

	public inline function endFrame()
		Platform.os() == 1 ? mtl().endFrame() : Platform.os() == 2 ? d3d().endFrame() : Platform.os() != 3 ? gl().endFrame() : webgl() ? gl().endFrame() : wgpu().endFrame();

	public inline function readPixels(dst:haxe.io.Bytes)
		Platform.os() == 1 ? mtl().readPixels(dst) : Platform.os() == 2 ? d3d().readPixels(dst) : Platform.os() != 3 ? gl().readPixels(dst) : webgl() ? gl().readPixels(dst) : wgpu().readPixels(dst);

	// (shared textures: Metal's, D3D11's and GL's; none in a browser)
	public inline function sharing():Null<String>
		return Platform.os() == 1 ? mtl().sharing() : Platform.os() == 2 ? d3d().sharing() : Platform.os() != 3 ? gl().sharing() : null;

	public inline function createShared(width:Int, height:Int):Null<{id:Int, handle:String}>
		return Platform.os() == 1 ? mtl().createShared(width, height) : Platform.os() == 2 ? d3d().createShared(width, height) : Platform.os() != 3 ? gl().createShared(width,
			height) : null;

	public inline function openShared(handle:String, width:Int, height:Int):Int
		return Platform.os() == 1 ? mtl().openShared(handle, width, height) : Platform.os() == 2 ? d3d().openShared(handle, width, height) : Platform.os() != 3 ? gl().openShared(handle,
			width, height) : 0;

	public inline function frameInto(id:Int)
		Platform.os() == 1 ? mtl().frameInto(id) : Platform.os() == 2 ? d3d().frameInto(id) : Platform.os() != 3 ? gl().frameInto(id) : if (id != 0) throw "helder.gfx: frameInto: not in a browser";

	public inline function dispose()
		Platform.os() == 1 ? mtl().dispose() : Platform.os() == 2 ? d3d().dispose() : Platform.os() != 3 ? gl().dispose() : webgl() ? gl().dispose() : wgpu().dispose();
}
