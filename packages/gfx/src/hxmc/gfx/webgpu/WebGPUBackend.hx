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
// back asynchronously instead. Uniform blocks and textures are a bind group
// (group 0, its layout from the shaders' bindings; uniform blocks at dynamic
// offsets into one ring buffer, written each frame before the submit).
class WebGPUBackend {
	public final backend = Backend.WebGPU;
	public var width(default, null) = 0;
	public var height(default, null) = 0;

	final surface:Surface;
	final target:Int;
	final handles:Array<Int> = []; // what dispose releases
	final bindings = new Map<Int, Array<ShaderBinding>>(); // each shader's
	final infos = new Map<Int, TextureInfo>(); // each texture's
	var cursor = 0; // into the frame's uniform ring

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
		if (offset & 3 != 0 || size & 3 != 0) throw "hxmc.gfx: writeBuffer: WebGPU writes multiples of 4 bytes at multiples of 4";
		WebGPU.write_buffer(id, offset, Mem.addr(data).add(8 + dataOffset), size);
	}

	public function createTexture(d:TextureDesc):Int {
		var info = TextureInfo.of(d);
		// (the Bytes cannot move during the call: no collection in an import)
		var t = WebGPU.texture(info.width, info.height, cast info.format, info.levels, info.target ? 1 : 0, d.data == null ? Ptr.nil() : Mem.addr(d.data).add(8));
		infos.set(t, info);
		handles.push(t);
		return t;
	}

	public function writeTexture(id:Int, data:haxe.io.Bytes, x:Int, y:Int, w:Int, h:Int, dataOffset:Int, level:Int) {
		var info = infos.get(id);
		info.checkWrite(data, x, y, w, h, dataOffset, level);
		WebGPU.write_texture(id, x, y, info.w, info.h, level, Mem.addr(data).add(8 + dataOffset));
	}

	public function generateMips(id:Int) {
		infos.get(id).checkMips();
		WebGPU.generate_mips(id);
	}

	public function destroyBuffer(id:Int) {
		if (!handles.remove(id)) return;
		WebGPU.release(id);
	}

	public function destroyTexture(id:Int) {
		infos.remove(id);
		destroyBuffer(id);
	}

	public function createSampler(d:SamplerDesc):Int {
		var f:Filter = d.filter == null ? Linear : d.filter, w:Wrap = d.wrap == null ? Repeat : d.wrap;
		var s = WebGPU.sampler(cast f, d.mipFilter == null ? 0 : d.mipFilter == Nearest ? 1 : 2, cast w);
		handles.push(s);
		return s;
	}

	public function createShader(d:ShaderDesc):Int {
		if (d.code.wgsl == null) throw "hxmc.gfx: createShader: no WGSL source for the WebGPU back end";
		var s = Arena.scopedValue(a -> WebGPU.shader(a.cstring(d.code.wgsl)));
		bindings.set(s, d.code.bindings == null ? [] : d.code.bindings);
		handles.push(s);
		return s;
	}

	public function createPipeline(d:PipelineDesc):Int {
		WebGPU.pipeline_begin();
		for (l in d.layout) {
			WebGPU.pipeline_buffer(l.stride, l.step == Instance ? 1 : 0);
			for (a in l.attributes)
				WebGPU.pipeline_attribute(a.location, cast a.format, a.offset);
		}
		var seen = 0;
		for (b in bindings.get(d.vertex.id()).concat(bindings.get(d.fragment.id())))
			if (seen & (1 << b.slot) == 0) {
				seen |= 1 << b.slot;
				WebGPU.pipeline_binding(b.slot, cast b.kind, b.size == null ? 0 : b.size);
			}
		var topology:Topology = d.topology == null ? Triangles : d.topology, cull:Cull = d.cull == null ? None : d.cull;
		var blend:Blend = d.blend == null ? Opaque : d.blend, compare:Compare = d.depthCompare == null ? Always : d.depthCompare;
		var color = d.colorFormat == null ? -1 : (cast d.colorFormat : Int);
		var depth = d.depthFormat != null ? (cast d.depthFormat : Int) : d.colorFormat == null ? (cast TextureFormat.Depth32F : Int) : -1;
		var p = WebGPU.pipeline_end(d.vertex.id(), d.fragment.id(), target, cast topology, cast cull, cast blend, cast compare, d.depthWrite == true ? 1 : 0,
			color, depth);
		handles.push(p);
		return p;
	}

	public function beginFrame():Bool {
		// (a canvas: its size now, which App's Resize events follow)
		cursor = 0;
		width = surface.width;
		height = surface.height;
		return WebGPU.frame_begin(target) != 0;
	}

	public function beginPass(p:PassDesc) {
		var c = p.colors[0], k = c.clear, d = p.depth;
		var depthLoad:LoadOp = d == null ? Load : d.load, depth = d == null || d.clear == null ? 1.0 : d.clear;
		var color = c.texture == null ? 0 : c.texture.id(), depthTexture = d == null || d.texture == null ? 0 : d.texture.id();
		if (color != 0) infos.get(color).checkPass(d);
		if (k == null) WebGPU.pass_begin(color, cast c.load, 0, 0, 0, 1, depthTexture, cast depthLoad, depth) else
			WebGPU.pass_begin(color, cast c.load, k.r, k.g, k.b, k.a, depthTexture, cast depthLoad, depth);
	}

	public inline function setPipeline(id:Int)
		WebGPU.set_pipeline(id);

	public inline function setVertexBuffer(slot:Int, id:Int, offset:Int)
		WebGPU.set_vertex_buffer(slot, id, offset);

	public function setUniforms(slot:Int, data:haxe.io.Bytes, offset:Int, size:Int) {
		if (offset < 0 || size < 0 || offset + size > data.length) throw "hxmc.gfx: setUniforms: outside the data";
		var n = (size + 255) & ~255;
		if (cursor + n > Encoder.UNIFORM_RING) throw "hxmc.gfx: setUniforms: more than " + Encoder.UNIFORM_RING + " bytes of uniforms in a frame";
		WebGPU.set_uniforms(slot, cursor, Mem.addr(data).add(8 + offset), size);
		cursor += n;
	}

	public inline function draw(vertices:Int, instances:Int, first:Int)
		WebGPU.draw(vertices, instances, first);

	public inline function setTexture(slot:Int, texture:Int, sampler:Int)
		WebGPU.set_texture(slot, texture, sampler);

	public inline function setIndexBuffer(id:Int, format:IndexFormat, offset:Int)
		WebGPU.set_index_buffer(id, cast format, offset);

	public inline function drawIndexed(count:Int, instances:Int, first:Int, baseVertex:Int)
		WebGPU.draw_indexed(count, instances, first, baseVertex);

	public inline function endPass()
		WebGPU.pass_end();

	public inline function endFrame()
		WebGPU.frame_end();

	public function readPixels(dst:haxe.io.Bytes)
		throw "hxmc.gfx: readPixels: WebGPU reads back asynchronously (readPixels in packages/gfx/imports.mjs)";

	public function dispose() {
		for (h in handles)
			WebGPU.release(h);
		handles.resize(0);
	}
}
