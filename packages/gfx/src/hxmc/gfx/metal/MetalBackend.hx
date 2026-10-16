package hxmc.gfx.metal;

import hxmc.gfx.*;
import hxmc.gfx.metal.Metal;
import hxmc.os.Surface;
import hxmc.os.objc.*;
import hxmc.unsafe.*;

// The Metal back end (macOS): the system's default device and a command
// queue, rendering to a window's CAMetalLayer (each frame to its next
// drawable) or, headless, to an offscreen texture. A frame is a command
// buffer in an autorelease pool, a pass a render command encoder. Shaders
// are MSL compiled at run time (newLibraryWithSource), their entry point
// main0; vertex buffer slots are buffer indices VERTEX_BUFFERS + slot (the
// lower ones stay for uniforms). The colour target is BGRA8 (the layer's
// own format): readPixels swaps it to RGBA. Buffers and textures are
// shared with the CPU: a write waits for the last frame the GPU is still
// running (lastCmd) before it changes them. Textures have one of two
// sampler states (Linear, Nearest); the pass's textures are set again on
// each pass's encoder.
class MetalBackend {
	public final backend = Backend.Metal;
	public var width(default, null) = 0;
	public var height(default, null) = 0;

	final surface:Surface;
	final device:Ptr;
	final queue:Ptr;
	final layer:Ptr; // Cocoa: the CAMetalLayer
	final target:Ptr; // headless: the colour texture
	final pass:Ptr; // MTLRenderPassDescriptor, reused
	final attachment:Ptr; // its colour attachment 0
	// native memory: an out-parameter, the structs passed by value
	final scratch:Ptr<Ptr>;
	final clear:Ptr<MTLClearColor>;
	final viewport:Ptr<MTLViewport>;
	final origin:Ptr<MTLOrigin>;
	final size:Ptr<MTLSize>;
	final region:Ptr<MTLRegion>;
	final scissor:Ptr<MTLScissorRect>;
	var readback = Ptr.nil(); // readPixels' MTLBuffer
	var readbackSize = 0;

	// tables (handle = index + 1)
	final buffers:Array<Ptr> = [];
	final shaders:Array<Ptr> = []; // MTLFunction
	final libraries:Array<Ptr> = [];
	final pipelines:Array<MtlPipeline> = [];
	final textures:Array<MtlTexture> = [];
	final samplers:Array<Ptr> = [Ptr.nil(), Ptr.nil()]; // MTLSamplerState by Filter
	final bound:Array<Int> = [for (_ in 0...MAX_TEXTURES) 0]; // the textures by slot
	var lastCmd = Ptr.nil(); // the last frame's command buffer (retained) until a write waits for it

	// the frame
	var pool = Ptr.nil();
	var cmd = Ptr.nil();
	var drawable = Ptr.nil();
	var texture = Ptr.nil();
	var enc = Ptr.nil();
	var pipeline:MtlPipeline = null;

	static inline var VERTEX_BUFFERS = 16;
	static inline var MAX_SLOTS = 8;
	static inline var MAX_TEXTURES = 8;

	public function new(surface:Surface) {
		this.surface = surface;
		var pool = Runtime.objc_autoreleasePoolPush();
		device = Metal.MTLCreateSystemDefaultDevice();
		if (device.isNull()) throw "hxmc.gfx: no Metal device";
		queue = Msg.id(device, ObjC.sel("newCommandQueue"));
		scratch = LibC.malloc(8);
		clear = LibC.malloc(32);
		viewport = LibC.malloc(48);
		origin = LibC.malloc(24);
		size = LibC.malloc(24);
		region = LibC.malloc(48);
		scissor = LibC.malloc(32);
		pass = make("MTLRenderPassDescriptor");
		attachment = Msg.idInt(Msg.id(pass, ObjC.sel("colorAttachments")), ObjC.sel("objectAtIndexedSubscript:"), 0);
		if (surface.kind == Cocoa) {
			layer = surface.display;
			target = Ptr.nil();
			Msg.vPtr(layer, ObjC.sel("setDevice:"), device);
			Msg.vInt(layer, ObjC.sel("setPixelFormat:"), MTL.PixelFormatBGRA8Unorm);
			// (readPixels copies from the drawable's texture)
			Msg.vBool(layer, ObjC.sel("setFramebufferOnly:"), false);
		} else {
			layer = Ptr.nil();
			var d = make("MTLTextureDescriptor");
			Msg.vInt(d, ObjC.sel("setPixelFormat:"), MTL.PixelFormatBGRA8Unorm);
			Msg.vInt(d, ObjC.sel("setWidth:"), surface.width);
			Msg.vInt(d, ObjC.sel("setHeight:"), surface.height);
			Msg.vInt(d, ObjC.sel("setUsage:"), MTL.TextureUsageRenderTarget);
			Msg.vInt(d, ObjC.sel("setStorageMode:"), MTL.StorageModePrivate);
			target = Msg.idPtr(device, ObjC.sel("newTextureWithDescriptor:"), d);
			Runtime.objc_release(d);
			if (target.isNull()) throw "hxmc.gfx: cannot create a " + surface.width + "x" + surface.height + " texture";
		}
		width = surface.width;
		height = surface.height;
		Runtime.objc_autoreleasePoolPop(pool);
	}

	// a new instance of a class ([[cls alloc] init]: owned, not autoreleased)
	static inline function make(cls:String):Ptr
		return Msg.id(Msg.id(ObjC.cls(cls), ObjC.sel("alloc")), ObjC.sel("init"));

	// an NSError's description
	static function describe(error:Ptr):String
		return error.isNull() ? "(no error)" : ObjC.string(Msg.id(error, ObjC.sel("localizedDescription")));

	public function createBuffer(d:BufferDesc):Int {
		var data = d.data, size = d.size;
		if (data != null && data.length < size) throw "hxmc.gfx: createBuffer: data has fewer than size bytes";
		var b = Msg.idIntInt(device, ObjC.sel("newBufferWithLength:options:"), size, MTL.ResourceStorageModeShared);
		if (b.isNull()) throw "hxmc.gfx: cannot create a buffer of " + size + " bytes";
		// (a fast call: the Bytes cannot move during it)
		if (data != null) LibC.memcpy(Msg.id(b, ObjC.sel("contents")), Mem.addr(data).add(8), (size : Int64));
		buffers.push(b);
		return buffers.length;
	}

	public function createShader(d:ShaderDesc):Int {
		if (d.code.msl == null) throw "hxmc.gfx: createShader: no MSL source for the Metal back end";
		var pool = Runtime.objc_autoreleasePoolPush();
		var src = ObjC.str(d.code.msl);
		scratch.value = Ptr.nil();
		var lib = Msg.idPtrPtrPtr(device, ObjC.sel("newLibraryWithSource:options:error:"), src, Ptr.nil(), scratch);
		ObjC.release(src);
		var error = lib.isNull() ? describe(scratch.value) : null;
		var fn = Ptr.nil();
		if (!lib.isNull()) {
			var name = ObjC.str("main0");
			fn = Msg.idPtr(lib, ObjC.sel("newFunctionWithName:"), name);
			ObjC.release(name);
		}
		Runtime.objc_autoreleasePoolPop(pool);
		if (error != null) throw "hxmc.gfx: the shader does not compile:\n" + error;
		if (fn.isNull()) throw "hxmc.gfx: the shader has no function main0";
		libraries.push(lib);
		shaders.push(fn);
		return shaders.length;
	}

	// waits for the last frame the GPU may still be reading
	function idle() {
		if (lastCmd.isNull()) return;
		Msg.v(lastCmd, ObjC.sel("waitUntilCompleted"));
		Runtime.objc_release(lastCmd);
		lastCmd = Ptr.nil();
	}

	public function writeBuffer(id:Int, offset:Int, data:haxe.io.Bytes, dataOffset:Int, size:Int) {
		idle();
		var b = buffers[id - 1];
		if (offset + size > Msg.i(b, ObjC.sel("length")).toInt()) throw "hxmc.gfx: writeBuffer: past the buffer's end";
		LibC.memcpy(Msg.id(b, ObjC.sel("contents")).add(offset), Mem.addr(data).add(8 + dataOffset), (size : Int64));
	}

	public function createTexture(d:TextureDesc):Int {
		var pool = Runtime.objc_autoreleasePoolPush();
		var desc = Msg.idIntIntIntBool(ObjC.cls("MTLTextureDescriptor"), ObjC.sel("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
			d.format == R8 ? MTL.PixelFormatR8Unorm : MTL.PixelFormatRGBA8Unorm, d.width, d.height, false);
		Msg.vInt(desc, ObjC.sel("setUsage:"), MTL.TextureUsageShaderRead);
		var tex = Msg.idPtr(device, ObjC.sel("newTextureWithDescriptor:"), desc);
		Runtime.objc_autoreleasePoolPop(pool);
		if (tex.isNull()) throw "hxmc.gfx: cannot create a " + d.width + "x" + d.height + " texture";
		var filter = d.filter == Nearest ? 1 : 0;
		if (samplers[filter].isNull()) {
			var sd = make("MTLSamplerDescriptor");
			var f = filter == 1 ? MTL.SamplerMinMagFilterNearest : MTL.SamplerMinMagFilterLinear;
			Msg.vInt(sd, ObjC.sel("setMinFilter:"), f);
			Msg.vInt(sd, ObjC.sel("setMagFilter:"), f);
			samplers[filter] = Msg.idPtr(device, ObjC.sel("newSamplerStateWithDescriptor:"), sd);
			Runtime.objc_release(sd);
		}
		var t = new MtlTexture(tex, samplers[filter], d.width, d.height, d.format.bytesPerPixel);
		textures.push(t);
		// (zeros unless given)
		var n = d.width * d.height * t.bpp;
		var data = d.data != null ? d.data : haxe.io.Bytes.alloc(n);
		replace(t, 0, 0, d.width, d.height, data, 0);
		return textures.length;
	}

	function replace(t:MtlTexture, x:Int, y:Int, w:Int, h:Int, data:haxe.io.Bytes, offset:Int) {
		region.value.x = x;
		region.value.y = y;
		region.value.z = 0;
		region.value.width = w;
		region.value.height = h;
		region.value.depth = 1;
		Arena.scoped(a -> MtlMsg.vRegion(t.texture, S.replaceRegion, region.value, 0, a.copyBytes(data, offset, w * h * t.bpp), w * t.bpp));
	}

	public function writeTexture(id:Int, x:Int, y:Int, w:Int, h:Int, data:haxe.io.Bytes, dataOffset:Int) {
		var t = textures[id - 1];
		if (x < 0 || y < 0 || x + w > t.width || y + h > t.height) throw "hxmc.gfx: writeTexture: outside the texture";
		idle();
		replace(t, x, y, w, h, data, dataOffset);
	}

	public function setTexture(slot:Int, id:Int) {
		bound[slot] = id;
		if (!enc.isNull()) bindTexture(slot);
	}

	function bindTexture(slot:Int) {
		var id = bound[slot];
		var t = id == 0 ? null : textures[id - 1];
		MtlMsg.vPtrInt(enc, S.setFragmentTexture, t == null ? Ptr.nil() : t.texture, slot);
		MtlMsg.vPtrInt(enc, S.setFragmentSamplerState, t == null ? Ptr.nil() : t.sampler, slot);
	}

	public function setScissor(x:Int, y:Int, w:Int, h:Int) {
		var x0 = x < 0 ? 0 : x > width ? width : x, y0 = y < 0 ? 0 : y > height ? height : y;
		var x1 = x + w > width ? width : x + w, y1 = y + h > height ? height : y + h;
		scissor.value.x = x0;
		scissor.value.y = y0;
		scissor.value.width = x1 < x0 ? 0 : x1 - x0;
		scissor.value.height = y1 < y0 ? 0 : y1 - y0;
		MtlMsg.vScissor(enc, S.setScissorRect, scissor.value);
	}

	public function createPipeline(d:PipelineDesc):Int {
		if (d.layout.length > MAX_SLOTS) throw "hxmc.gfx: more than " + MAX_SLOTS + " vertex buffers";
		var pool = Runtime.objc_autoreleasePoolPush();
		var desc = make("MTLRenderPipelineDescriptor");
		Msg.vPtr(desc, ObjC.sel("setVertexFunction:"), shaders[d.vertex.id() - 1]);
		Msg.vPtr(desc, ObjC.sel("setFragmentFunction:"), shaders[d.fragment.id() - 1]);
		var color = Msg.idInt(Msg.id(desc, ObjC.sel("colorAttachments")), ObjC.sel("objectAtIndexedSubscript:"), 0);
		Msg.vInt(color, ObjC.sel("setPixelFormat:"), MTL.PixelFormatBGRA8Unorm);
		if (d.blend != null && d.blend != Replace) {
			Msg.vBool(color, ObjC.sel("setBlendingEnabled:"), true);
			Msg.vInt(color, ObjC.sel("setSourceRGBBlendFactor:"), d.blend == Alpha ? MTL.BlendFactorSourceAlpha : MTL.BlendFactorOne);
			Msg.vInt(color, ObjC.sel("setDestinationRGBBlendFactor:"), d.blend == Add ? MTL.BlendFactorOne : MTL.BlendFactorOneMinusSourceAlpha);
			Msg.vInt(color, ObjC.sel("setSourceAlphaBlendFactor:"), MTL.BlendFactorOne);
			Msg.vInt(color, ObjC.sel("setDestinationAlphaBlendFactor:"), MTL.BlendFactorOneMinusSourceAlpha);
		}
		var vd = make("MTLVertexDescriptor");
		var attributes = Msg.id(vd, ObjC.sel("attributes")), layouts = Msg.id(vd, ObjC.sel("layouts"));
		for (slot in 0...d.layout.length) {
			var l = d.layout[slot];
			Msg.vInt(Msg.idInt(layouts, ObjC.sel("objectAtIndexedSubscript:"), VERTEX_BUFFERS + slot), ObjC.sel("setStride:"), l.stride);
			for (a in l.attributes) {
				var ad = Msg.idInt(attributes, ObjC.sel("objectAtIndexedSubscript:"), a.location);
				Msg.vInt(ad, ObjC.sel("setFormat:"), switch a.format {
					case Float1: MTL.VertexFormatFloat;
					case Float2: MTL.VertexFormatFloat2;
					case Float3: MTL.VertexFormatFloat3;
					case Float4: MTL.VertexFormatFloat4;
					case UByte4Norm: MTL.VertexFormatUChar4Normalized;
				});
				Msg.vInt(ad, ObjC.sel("setOffset:"), a.offset);
				Msg.vInt(ad, ObjC.sel("setBufferIndex:"), VERTEX_BUFFERS + slot);
			}
		}
		Msg.vPtr(desc, ObjC.sel("setVertexDescriptor:"), vd);
		scratch.value = Ptr.nil();
		var state = Msg.idPtrPtr(device, ObjC.sel("newRenderPipelineStateWithDescriptor:error:"), desc, scratch);
		Runtime.objc_release(vd);
		Runtime.objc_release(desc);
		var error = state.isNull() ? describe(scratch.value) : null;
		Runtime.objc_autoreleasePoolPop(pool);
		if (error != null) throw "hxmc.gfx: the pipeline does not link:\n" + error;
		pipelines.push(new MtlPipeline(state, d));
		return pipelines.length;
	}

	// false: no drawable this frame (the window is hidden)
	public function beginFrame():Bool {
		pool = Runtime.objc_autoreleasePoolPush();
		if (layer.isNull()) texture = target else {
			drawable = Msg.id(layer, S.nextDrawable);
			if (drawable.isNull()) {
				Runtime.objc_autoreleasePoolPop(pool);
				return false;
			}
			texture = Msg.id(drawable, S.texture);
			width = Msg.i(texture, S.width).toInt();
			height = Msg.i(texture, S.height).toInt();
		}
		cmd = Msg.id(queue, S.commandBuffer);
		return true;
	}

	public function beginPass(p:PassDesc) {
		var c = p.colors[0];
		Msg.vPtr(attachment, S.setTexture, texture);
		Msg.vInt(attachment, S.setLoadAction, switch c.load {
			case Clear: MTL.LoadActionClear;
			case Load: MTL.LoadActionLoad;
			case DontCare: MTL.LoadActionDontCare;
		});
		Msg.vInt(attachment, S.setStoreAction, MTL.StoreActionStore);
		if (c.load == Clear) {
			var k = c.clear;
			clear.value.red = k == null ? 0 : k.r;
			clear.value.green = k == null ? 0 : k.g;
			clear.value.blue = k == null ? 0 : k.b;
			clear.value.alpha = k == null ? 1 : k.a;
			MtlMsg.vClear(attachment, S.setClearColor, clear.value);
		}
		enc = Msg.idPtr(cmd, S.renderCommandEncoderWithDescriptor, pass);
		viewport.value.originX = 0;
		viewport.value.originY = 0;
		viewport.value.width = width;
		viewport.value.height = height;
		viewport.value.znear = 0;
		viewport.value.zfar = 1;
		MtlMsg.vViewport(enc, S.setViewport, viewport.value);
		// (GL's front faces)
		Msg.vInt(enc, S.setFrontFacingWinding, MTL.WindingCounterClockwise);
		pipeline = null;
		for (i in 0...MAX_TEXTURES)
			if (bound[i] != 0) bindTexture(i);
	}

	public function setPipeline(id:Int) {
		var p = pipelines[id - 1];
		if (p == pipeline) return;
		pipeline = p;
		Msg.vPtr(enc, S.setRenderPipelineState, p.state);
		Msg.vInt(enc, S.setCullMode, p.cull);
	}

	public function setVertexBuffer(slot:Int, id:Int, offset:Int)
		MtlMsg.vPtrIntInt(enc, S.setVertexBuffer, buffers[id - 1], offset, VERTEX_BUFFERS + slot);

	public function draw(vertices:Int, instances:Int, first:Int)
		MtlMsg.vIntIntIntInt(enc, S.drawPrimitives, pipeline.topology, first, vertices, instances);

	public function endPass() {
		Msg.v(enc, S.endEncoding);
		enc = Ptr.nil();
	}

	public function endFrame() {
		if (!drawable.isNull()) Msg.vPtr(cmd, S.presentDrawable, drawable);
		Msg.v(cmd, S.commit);
		if (!lastCmd.isNull()) Runtime.objc_release(lastCmd);
		lastCmd = Runtime.objc_retain(cmd);
		cmd = Ptr.nil();
		drawable = Ptr.nil();
		texture = Ptr.nil();
		Runtime.objc_autoreleasePoolPop(pool);
		pool = Ptr.nil();
	}

	// the frame's passes so far, then a copy of the target into a shared
	// buffer, waited for; the frame goes on in a new command buffer
	public function readPixels(dst:haxe.io.Bytes) {
		var row = width * 4, n = row * height;
		if (dst.length < n) throw "hxmc.gfx: readPixels: " + n + " bytes needed";
		if (readbackSize < n) {
			ObjC.release(readback);
			readback = Msg.idIntInt(device, ObjC.sel("newBufferWithLength:options:"), n, MTL.ResourceStorageModeShared);
			readbackSize = n;
		}
		var blit = Msg.id(cmd, ObjC.sel("blitCommandEncoder"));
		origin.value.x = 0;
		origin.value.y = 0;
		origin.value.z = 0;
		size.value.width = width;
		size.value.height = height;
		size.value.depth = 1;
		MtlMsg.vCopy(blit, ObjC.sel("copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toBuffer:destinationOffset:destinationBytesPerRow:destinationBytesPerImage:"),
			texture, 0, 0, origin.value, size.value, readback, 0, row, n);
		Msg.v(blit, S.endEncoding);
		Msg.v(cmd, S.commit);
		Msg.v(cmd, ObjC.sel("waitUntilCompleted"));
		if (Msg.i(cmd, ObjC.sel("status")) == MTL.CommandBufferStatusError)
			throw "hxmc.gfx: the GPU failed: " + describe(Msg.id(cmd, ObjC.sel("error")));
		cmd = Msg.id(queue, S.commandBuffer);
		var src:Ptr<UInt8> = Msg.id(readback, ObjC.sel("contents"));
		for (i in 0...width * height) {
			dst.set(4 * i, src[4 * i + 2]);
			dst.set(4 * i + 1, src[4 * i + 1]);
			dst.set(4 * i + 2, src[4 * i]);
			dst.set(4 * i + 3, src[4 * i + 3]);
		}
	}

	public function dispose() {
		for (p in pipelines)
			Runtime.objc_release(p.state);
		idle();
		for (o in shaders.concat(libraries).concat(buffers))
			Runtime.objc_release(o);
		for (t in textures)
			Runtime.objc_release(t.texture);
		for (s in samplers)
			ObjC.release(s);
		ObjC.release(readback);
		ObjC.release(target);
		Runtime.objc_release(pass);
		Runtime.objc_release(queue);
		if (!layer.isNull()) Msg.vPtr(layer, ObjC.sel("setDevice:"), Ptr.nil());
		Runtime.objc_release(device);
		LibC.free(scratch);
		LibC.free(clear);
		LibC.free(viewport);
		LibC.free(origin);
		LibC.free(size);
		LibC.free(region);
		LibC.free(scissor);
	}
}

// a texture and its sampler state (shared)
private class MtlTexture {
	public final texture:Ptr;
	public final sampler:Ptr;
	public final width:Int;
	public final height:Int;
	public final bpp:Int;

	public function new(texture:Ptr, sampler:Ptr, width:Int, height:Int, bpp:Int) {
		this.texture = texture;
		this.sampler = sampler;
		this.width = width;
		this.height = height;
		this.bpp = bpp;
	}
}

// a render pipeline state and its draw state
private class MtlPipeline {
	public final state:Ptr;
	public final topology:Int;
	public final cull:Int;

	public function new(state:Ptr, d:PipelineDesc) {
		this.state = state;
		topology = switch d.topology {
			case null | Triangles: MTL.PrimitiveTypeTriangle;
			case TriangleStrip: MTL.PrimitiveTypeTriangleStrip;
			case Lines: MTL.PrimitiveTypeLine;
			case Points: MTL.PrimitiveTypePoint;
		}
		cull = switch d.cull {
			case null | None: MTL.CullModeNone;
			case Front: MTL.CullModeFront;
			case Back: MTL.CullModeBack;
		}
	}
}

// the selectors of a frame's messages, registered once
private class S {
	public static final nextDrawable = ObjC.sel("nextDrawable");
	public static final texture = ObjC.sel("texture");
	public static final width = ObjC.sel("width");
	public static final height = ObjC.sel("height");
	public static final commandBuffer = ObjC.sel("commandBuffer");
	public static final setTexture = ObjC.sel("setTexture:");
	public static final setLoadAction = ObjC.sel("setLoadAction:");
	public static final setStoreAction = ObjC.sel("setStoreAction:");
	public static final setClearColor = ObjC.sel("setClearColor:");
	public static final renderCommandEncoderWithDescriptor = ObjC.sel("renderCommandEncoderWithDescriptor:");
	public static final setViewport = ObjC.sel("setViewport:");
	public static final setFrontFacingWinding = ObjC.sel("setFrontFacingWinding:");
	public static final setRenderPipelineState = ObjC.sel("setRenderPipelineState:");
	public static final setCullMode = ObjC.sel("setCullMode:");
	public static final setVertexBuffer = ObjC.sel("setVertexBuffer:offset:atIndex:");
	public static final drawPrimitives = ObjC.sel("drawPrimitives:vertexStart:vertexCount:instanceCount:");
	public static final endEncoding = ObjC.sel("endEncoding");
	public static final presentDrawable = ObjC.sel("presentDrawable:");
	public static final commit = ObjC.sel("commit");
	public static final replaceRegion = ObjC.sel("replaceRegion:mipmapLevel:withBytes:bytesPerRow:");
	public static final setFragmentTexture = ObjC.sel("setFragmentTexture:atIndex:");
	public static final setFragmentSamplerState = ObjC.sel("setFragmentSamplerState:atIndex:");
	public static final setScissorRect = ObjC.sel("setScissorRect:");
}
