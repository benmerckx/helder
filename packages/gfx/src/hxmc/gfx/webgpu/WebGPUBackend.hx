package hxmc.gfx.webgpu;

import hxmc.gfx.*;
import hxmc.os.Surface;
import hxmc.unsafe.*;

// The WebGPU back end (the browser, WebAssembly): the device imports.mjs
// requested before main, rendering to a canvas (each frame to its current
// texture, presented by the browser after the frame's task) or, headless,
// to a texture. A frame is a command encoder, a pass a render pass encoder.
// Shaders are WGSL, their entry point main; pipelines are made from the
// vertex layout and the target's format. Every call is a JavaScript import
// with integer arguments (GPU objects are handles of the JavaScript side),
// so a frame allocates nothing here. readPixels cannot wait for the GPU in
// a browser: the JavaScript side's readPixels (imports.mjs) reads a frame
// back asynchronously instead.
class WebGPUBackend {
	public final backend = Backend.WebGPU;
	public var width(default, null) = 0;
	public var height(default, null) = 0;

	final surface:Surface;
	final target:Int;
	final handles:Array<Int> = []; // what dispose releases

	public function new(surface:Surface) {
		this.surface = surface;
		if (WebGPU.ready() == 0) throw "hxmc.gfx: no WebGPU device";
		target = switch surface.kind {
			case Canvas: WebGPU.target_canvas(surface.handle.toI64().toInt());
			case Headless: WebGPU.target_texture(surface.width, surface.height);
			case k: throw "hxmc.gfx: WebGPU renders to a canvas or headless, not to a surface of kind " + k;
		}
		handles.push(target);
		width = surface.width;
		height = surface.height;
	}

	public function createBuffer(d:BufferDesc):Int {
		var data = d.data, size = d.size;
		if (data != null && data.length < size) throw "hxmc.gfx: createBuffer: data has fewer than size bytes";
		// (the Bytes cannot move during the call: no collection in an import)
		var b = WebGPU.buffer(size, cast d.usage, data == null ? Ptr.nil() : Mem.addr(data).add(8), data == null ? 0 : size);
		handles.push(b);
		return b;
	}

	public function writeBuffer(id:Int, offset:Int, data:haxe.io.Bytes, dataOffset:Int, size:Int) {
		if (offset & 3 != 0 || size & 3 != 0) throw "hxmc.gfx: writeBuffer: WebGPU writes multiples of 4 bytes at offsets of 4";
		WebGPU.write_buffer(id, offset, Mem.addr(data).add(8 + dataOffset), size);
	}

	public function createTexture(d:TextureDesc):Int {
		var data = d.data;
		var t = WebGPU.texture(d.width, d.height, cast d.format, d.filter == null ? 0 : cast d.filter, data == null ? Ptr.nil() : Mem.addr(data).add(8));
		handles.push(t);
		return t;
	}

	public function writeTexture(id:Int, x:Int, y:Int, w:Int, h:Int, data:haxe.io.Bytes, dataOffset:Int)
		WebGPU.write_texture(id, x, y, w, h, Mem.addr(data).add(8 + dataOffset));

	public inline function setTexture(slot:Int, id:Int)
		WebGPU.set_texture(slot, id);

	public inline function setScissor(x:Int, y:Int, w:Int, h:Int)
		WebGPU.set_scissor(x, y, w, h);

	public function createShader(d:ShaderDesc):Int {
		if (d.code.wgsl == null) throw "hxmc.gfx: createShader: no WGSL source for the WebGPU back end";
		var s = Arena.scopedValue(a -> WebGPU.shader(a.cstring(d.code.wgsl)));
		handles.push(s);
		return s;
	}

	public function createPipeline(d:PipelineDesc):Int {
		WebGPU.pipeline_begin();
		for (l in d.layout) {
			WebGPU.pipeline_buffer(l.stride);
			for (a in l.attributes)
				WebGPU.pipeline_attribute(a.location, cast a.format, a.offset);
		}
		var topology:Topology = d.topology == null ? Triangles : d.topology, cull:Cull = d.cull == null ? None : d.cull;
		var blend:Blend = d.blend == null ? Replace : d.blend;
		var p = WebGPU.pipeline_end(d.vertex.id(), d.fragment.id(), target, cast topology, cast cull, cast blend, d.textures == null ? 0 : d.textures);
		handles.push(p);
		return p;
	}

	public function beginFrame():Bool {
		// (a canvas: its size now, which App's Resize events follow)
		width = surface.width;
		height = surface.height;
		return WebGPU.frame_begin(target) != 0;
	}

	public function beginPass(p:PassDesc) {
		var c = p.colors[0], k = c.clear;
		if (k == null) WebGPU.pass_begin(cast c.load, 0, 0, 0, 1) else WebGPU.pass_begin(cast c.load, k.r, k.g, k.b, k.a);
	}

	public inline function setPipeline(id:Int)
		WebGPU.set_pipeline(id);

	public inline function setVertexBuffer(slot:Int, id:Int, offset:Int)
		WebGPU.set_vertex_buffer(slot, id, offset);

	public inline function draw(vertices:Int, instances:Int, first:Int)
		WebGPU.draw(vertices, instances, first);

	public inline function endPass()
		WebGPU.pass_end();

	public inline function endFrame()
		WebGPU.frame_end();

	public function readPixels(dst:haxe.io.Bytes)
		throw "hxmc.gfx: readPixels: WebGPU reads back asynchronously (readPixels in packages/gfx/imports.mjs)";

	public function destroyBuffer(id:Int) {
		if (!handles.remove(id)) return;
		WebGPU.release(id);
	}

	public function destroyTexture(id:Int)
		destroyBuffer(id);

	public function dispose() {
		for (h in handles)
			WebGPU.release(h);
		handles.resize(0);
	}
}
