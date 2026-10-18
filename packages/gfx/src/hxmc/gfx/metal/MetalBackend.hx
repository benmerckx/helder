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
// lower ones are the uniform blocks' slots: setUniforms copies a block
// into the command stream, setVertexBytes and setFragmentBytes, at most
// 4 KB). The colour target is BGRA8 (the layer's own format): readPixels
// swaps it to RGBA. The depth buffer is a Depth32Float texture of the target's size,
// remade when the drawable's size changes. A texture at slot n is [[texture(n)]] and its
// sampler [[sampler(n)]], in both stages. A render target is a texture in
// the GPU's memory (StorageModePrivate); generateMips is a blit.
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
	final depthAttachment:Ptr; // and its depth attachment
	var depth = Ptr.nil(); // the depth texture, of depthWidth x depthHeight
	var depthWidth = 0;
	var depthHeight = 0;
	// native memory: an out-parameter, the structs passed by value
	final scratch:Ptr<Ptr>;
	final clear:Ptr<MTLClearColor>;
	final viewport:Ptr<MTLViewport>;
	final origin:Ptr<MTLOrigin>;
	final size:Ptr<MTLSize>;
	final uniforms:Ptr<UInt8>; // a block on its way to setVertexBytes (MAX_BYTES)
	var readback = Ptr.nil(); // readPixels' MTLBuffer
	final region:Ptr<MTLRegion>; // writeTexture's
	var readbackSize = 0;

	// tables (handle = index + 1)
	final buffers:Array<Ptr> = [];
	final shaders:Array<Ptr> = []; // MTLFunction
	final libraries:Array<Ptr> = [];
	final pipelines:Array<MtlPipeline> = [];
	final textures:Array<Ptr> = []; // MTLTexture
	final infos:Array<TextureInfo> = [];
	final samplers:Array<Ptr> = []; // MTLSamplerState

	// the frame
	var pool = Ptr.nil();
	var cmd = Ptr.nil();
	var drawable = Ptr.nil();
	var texture = Ptr.nil();
	var enc = Ptr.nil();
	var pipeline:MtlPipeline = null;
	// drawIndexed's index buffer, type (MTL.IndexType*) and offset
	var ibuf = Ptr.nil();
	var itype = 0;
	var ioffset = 0;

	static inline var VERTEX_BUFFERS = 16;
	static inline var MAX_SLOTS = 8;
	static inline var MAX_BYTES = 4096;

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
		uniforms = LibC.malloc(MAX_BYTES);
		pass = make("MTLRenderPassDescriptor");
		attachment = Msg.idInt(Msg.id(pass, ObjC.sel("colorAttachments")), ObjC.sel("objectAtIndexedSubscript:"), 0);
		depthAttachment = Msg.id(pass, ObjC.sel("depthAttachment"));
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

	// the depth texture, when the target's size is not its own
	function sizeDepth() {
		if (depthWidth == width && depthHeight == height) return;
		ObjC.release(depth);
		var d = make("MTLTextureDescriptor");
		Msg.vInt(d, ObjC.sel("setPixelFormat:"), MTL.PixelFormatDepth32Float);
		Msg.vInt(d, ObjC.sel("setWidth:"), width);
		Msg.vInt(d, ObjC.sel("setHeight:"), height);
		Msg.vInt(d, ObjC.sel("setUsage:"), MTL.TextureUsageRenderTarget);
		Msg.vInt(d, ObjC.sel("setStorageMode:"), MTL.StorageModePrivate);
		depth = Msg.idPtr(device, ObjC.sel("newTextureWithDescriptor:"), d);
		Runtime.objc_release(d);
		if (depth.isNull()) throw "hxmc.gfx: cannot create a " + width + "x" + height + " depth texture";
		depthWidth = width;
		depthHeight = height;
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

	// (shared memory: what the GPU reads when the frame runs)
	public function writeBuffer(id:Int, offset:Int, data:haxe.io.Bytes, dataOffset:Int, size:Int) {
		var b = buffers[id - 1];
		if (offset + size > Msg.i(b, ObjC.sel("length")).toInt()) throw "hxmc.gfx: writeBuffer: past the buffer's end";
		var dst:Ptr<UInt8> = Msg.id(b, ObjC.sel("contents"));
		LibC.memcpy(dst.add(offset), Mem.addr(data).add(8 + dataOffset), (size : Int64));
	}

	static function pixelFormat(f:TextureFormat):Int
		return switch f {
			case RGBA8: MTL.PixelFormatRGBA8Unorm;
			case RGBA8Srgb: MTL.PixelFormatRGBA8UnormSrgb;
			case R8: MTL.PixelFormatR8Unorm;
			case RG8: MTL.PixelFormatRG8Unorm;
			case RGBA16F: MTL.PixelFormatRGBA16Float;
			case R32F: MTL.PixelFormatR32Float;
			case Depth16: MTL.PixelFormatDepth16Unorm;
			case Depth32F: MTL.PixelFormatDepth32Float;
		}

	public function createTexture(d:TextureDesc):Int {
		var info = TextureInfo.of(d), target = info.target;
		var desc = make("MTLTextureDescriptor");
		Msg.vInt(desc, ObjC.sel("setPixelFormat:"), pixelFormat(info.format));
		Msg.vInt(desc, ObjC.sel("setWidth:"), info.width);
		Msg.vInt(desc, ObjC.sel("setHeight:"), info.height);
		Msg.vInt(desc, ObjC.sel("setMipmapLevelCount:"), info.levels);
		// (a render target: in the GPU's memory only, as depth textures must be)
		Msg.vInt(desc, ObjC.sel("setUsage:"), target ? MTL.TextureUsageShaderRead | MTL.TextureUsageRenderTarget : MTL.TextureUsageShaderRead);
		if (target) Msg.vInt(desc, ObjC.sel("setStorageMode:"), MTL.StorageModePrivate);
		var t = Msg.idPtr(device, ObjC.sel("newTextureWithDescriptor:"), desc);
		Runtime.objc_release(desc);
		if (t.isNull()) throw "hxmc.gfx: cannot create a " + d.width + "x" + d.height + " texture";
		textures.push(t);
		infos.push(info);
		if (d.data != null) writeTexture(textures.length, d.data, 0, 0, -1, -1, 0, 0);
		return textures.length;
	}

	public function writeTexture(id:Int, data:haxe.io.Bytes, x:Int, y:Int, w:Int, h:Int, dataOffset:Int, level:Int) {
		var t = textures[id - 1], info = infos[id - 1];
		info.checkWrite(data, x, y, w, h, dataOffset, level);
		w = info.w;
		h = info.h;
		var n = info.format.texelSize;
		region.value.origin.x = x;
		region.value.origin.y = y;
		region.value.origin.z = 0;
		region.value.size.width = w;
		region.value.size.height = h;
		region.value.size.depth = 1;
		// (a copy first: the Bytes may move during a message)
		Arena.scoped(a -> MtlMsg.vRegionIntPtrInt(t, ObjC.sel("replaceRegion:mipmapLevel:withBytes:bytesPerRow:"), region.value, level, a.copyBytes(data, dataOffset, w * h * n), w * n));
	}

	// a blit in the frame's command buffer (between its passes), else in one of its own
	public function generateMips(id:Int) {
		infos[id - 1].checkMips();
		var own = cmd.isNull();
		var pool = own ? Runtime.objc_autoreleasePoolPush() : Ptr.nil();
		var c = own ? Msg.id(queue, S.commandBuffer) : cmd;
		var blit = Msg.id(c, ObjC.sel("blitCommandEncoder"));
		Msg.vPtr(blit, ObjC.sel("generateMipmapsForTexture:"), textures[id - 1]);
		Msg.v(blit, S.endEncoding);
		if (own) {
			Msg.v(c, S.commit);
			Runtime.objc_autoreleasePoolPop(pool);
		}
	}

	public function destroyBuffer(id:Int) {
		var b = buffers[id - 1];
		if (b.isNull()) return;
		Runtime.objc_release(b);
		buffers[id - 1] = Ptr.nil();
	}

	public function destroyTexture(id:Int) {
		var t = textures[id - 1];
		if (t.isNull()) return;
		Runtime.objc_release(t);
		textures[id - 1] = Ptr.nil();
	}

	public function createSampler(d:SamplerDesc):Int {
		var desc = make("MTLSamplerDescriptor");
		var f = d.filter == Nearest ? MTL.SamplerMinMagFilterNearest : MTL.SamplerMinMagFilterLinear;
		var w = switch d.wrap {
			case null | Repeat: MTL.SamplerAddressModeRepeat;
			case Clamp: MTL.SamplerAddressModeClampToEdge;
			case Mirror: MTL.SamplerAddressModeMirrorRepeat;
		}
		Msg.vInt(desc, ObjC.sel("setMinFilter:"), f);
		Msg.vInt(desc, ObjC.sel("setMagFilter:"), f);
		Msg.vInt(desc, ObjC.sel("setMipFilter:"), d.mipFilter == null ? 0 : d.mipFilter == Nearest ? 1 : 2);
		Msg.vInt(desc, ObjC.sel("setSAddressMode:"), w);
		Msg.vInt(desc, ObjC.sel("setTAddressMode:"), w);
		var s = Msg.idPtr(device, ObjC.sel("newSamplerStateWithDescriptor:"), desc);
		Runtime.objc_release(desc);
		if (s.isNull()) throw "hxmc.gfx: cannot create a sampler";
		samplers.push(s);
		return samplers.length;
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

	public function createPipeline(d:PipelineDesc):Int {
		if (d.layout.length > MAX_SLOTS) throw "hxmc.gfx: more than " + MAX_SLOTS + " vertex buffers";
		var pool = Runtime.objc_autoreleasePoolPush();
		var desc = make("MTLRenderPipelineDescriptor");
		Msg.vPtr(desc, ObjC.sel("setVertexFunction:"), shaders[d.vertex.id() - 1]);
		Msg.vPtr(desc, ObjC.sel("setFragmentFunction:"), shaders[d.fragment.id() - 1]);
		var color = Msg.idInt(Msg.id(desc, ObjC.sel("colorAttachments")), ObjC.sel("objectAtIndexedSubscript:"), 0);
		Msg.vInt(color, ObjC.sel("setPixelFormat:"), d.colorFormat == null ? MTL.PixelFormatBGRA8Unorm : pixelFormat(d.colorFormat));
		var blend:Blend = d.blend == null ? Opaque : d.blend;
		if (blend != Opaque) {
			Msg.vBool(color, ObjC.sel("setBlendingEnabled:"), true);
			Msg.vInt(color, ObjC.sel("setSourceRGBBlendFactor:"), blend == Premultiplied ? MTL.BlendFactorOne : MTL.BlendFactorSourceAlpha);
			Msg.vInt(color, ObjC.sel("setDestinationRGBBlendFactor:"), blend == Additive ? MTL.BlendFactorOne : MTL.BlendFactorOneMinusSourceAlpha);
			Msg.vInt(color, ObjC.sel("setRgbBlendOperation:"), MTL.BlendOperationAdd);
			Msg.vInt(color, ObjC.sel("setSourceAlphaBlendFactor:"), MTL.BlendFactorOne);
			Msg.vInt(color, ObjC.sel("setDestinationAlphaBlendFactor:"), blend == Additive ? MTL.BlendFactorOne : MTL.BlendFactorOneMinusSourceAlpha);
			Msg.vInt(color, ObjC.sel("setAlphaBlendOperation:"), MTL.BlendOperationAdd);
		}
		Msg.vInt(desc, ObjC.sel("setDepthAttachmentPixelFormat:"), d.depthFormat != null ? pixelFormat(d.depthFormat) : d.colorFormat == null ? MTL.PixelFormatDepth32Float : MTL.PixelFormatInvalid);
		var vd = make("MTLVertexDescriptor");
		var attributes = Msg.id(vd, ObjC.sel("attributes")), layouts = Msg.id(vd, ObjC.sel("layouts"));
		for (slot in 0...d.layout.length) {
			var l = d.layout[slot];
			var ld = Msg.idInt(layouts, ObjC.sel("objectAtIndexedSubscript:"), VERTEX_BUFFERS + slot);
			Msg.vInt(ld, ObjC.sel("setStride:"), l.stride);
			// (an instance buffer: one element per instance, the step rate 1 by default)
			if (l.step == Instance) Msg.vInt(ld, ObjC.sel("setStepFunction:"), MTL.VertexStepFunctionPerInstance);
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
		var ds = make("MTLDepthStencilDescriptor");
		Msg.vInt(ds, ObjC.sel("setDepthCompareFunction:"), d.depthCompare == null ? (cast Compare.Always : Int) : (cast d.depthCompare : Int));
		Msg.vBool(ds, ObjC.sel("setDepthWriteEnabled:"), d.depthWrite == true);
		var depthState = Msg.idPtr(device, ObjC.sel("newDepthStencilStateWithDescriptor:"), ds);
		Runtime.objc_release(ds);
		pipelines.push(new MtlPipeline(state, depthState, d));
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
		sizeDepth();
		cmd = Msg.id(queue, S.commandBuffer);
		return true;
	}

	public function beginPass(p:PassDesc) {
		var c = p.colors[0], d = p.depth, w = width, h = height;
		var depthTexture = depth;
		if (c.texture != null) {
			// (a render target, its depth texture or none)
			var info = infos[c.texture.id() - 1];
			info.checkPass(d);
			w = info.width;
			h = info.height;
			depthTexture = d == null ? Ptr.nil() : textures[d.texture.id() - 1];
		}
		Msg.vPtr(attachment, S.setTexture, c.texture == null ? texture : textures[c.texture.id() - 1]);
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
		Msg.vPtr(depthAttachment, S.setTexture, depthTexture);
		Msg.vInt(depthAttachment, S.setLoadAction, d == null || d.load == Load ? MTL.LoadActionLoad : MTL.LoadActionClear);
		Msg.vInt(depthAttachment, S.setStoreAction, MTL.StoreActionStore);
		Msg.vFloat(depthAttachment, S.setClearDepth, d == null || d.clear == null ? 1 : d.clear);
		enc = Msg.idPtr(cmd, S.renderCommandEncoderWithDescriptor, pass);
		viewport.value.originX = 0;
		viewport.value.originY = 0;
		viewport.value.width = w;
		viewport.value.height = h;
		viewport.value.znear = 0;
		viewport.value.zfar = 1;
		MtlMsg.vViewport(enc, S.setViewport, viewport.value);
		// (GL's front faces)
		Msg.vInt(enc, S.setFrontFacingWinding, MTL.WindingCounterClockwise);
		pipeline = null;
	}

	public function setPipeline(id:Int) {
		var p = pipelines[id - 1];
		if (p == pipeline) return;
		pipeline = p;
		Msg.vPtr(enc, S.setRenderPipelineState, p.state);
		Msg.vInt(enc, S.setCullMode, p.cull);
		Msg.vPtr(enc, S.setDepthStencilState, p.depth);
	}

	public function setVertexBuffer(slot:Int, id:Int, offset:Int)
		MtlMsg.vPtrIntInt(enc, S.setVertexBuffer, buffers[id - 1], offset, VERTEX_BUFFERS + slot);

	public function setUniforms(slot:Int, data:haxe.io.Bytes, offset:Int, size:Int) {
		if (offset < 0 || size < 0 || offset + size > data.length) throw "hxmc.gfx: setUniforms: outside the data";
		if (size > MAX_BYTES) throw "hxmc.gfx: setUniforms: a block of more than " + MAX_BYTES + " bytes";
		// (a copy first: the Bytes may move during a message)
		LibC.memcpy(uniforms, Mem.addr(data).add(8 + offset), (size : Int64));
		MtlMsg.vPtrIntInt(enc, S.setVertexBytes, uniforms, size, slot);
		MtlMsg.vPtrIntInt(enc, S.setFragmentBytes, uniforms, size, slot);
	}

	public function draw(vertices:Int, instances:Int, first:Int)
		MtlMsg.vIntIntIntInt(enc, S.drawPrimitives, pipeline.topology, first, vertices, instances);

	public function setTexture(slot:Int, texture:Int, sampler:Int) {
		var t = textures[texture - 1], s = samplers[sampler - 1];
		MtlMsg.vPtrInt(enc, S.setVertexTexture, t, slot);
		MtlMsg.vPtrInt(enc, S.setFragmentTexture, t, slot);
		MtlMsg.vPtrInt(enc, S.setVertexSamplerState, s, slot);
		MtlMsg.vPtrInt(enc, S.setFragmentSamplerState, s, slot);
	}

	public function setIndexBuffer(id:Int, format:IndexFormat, offset:Int) {
		ibuf = buffers[id - 1];
		itype = format == UInt16 ? MTL.IndexTypeUInt16 : MTL.IndexTypeUInt32;
		ioffset = offset;
	}

	public function drawIndexed(count:Int, instances:Int, first:Int, baseVertex:Int) {
		var at = ioffset + first * (itype == MTL.IndexTypeUInt16 ? 2 : 4);
		MtlMsg.vIntIntIntPtrIntIntIntInt(enc, S.drawIndexedPrimitives, pipeline.topology, count, itype, ibuf, at, instances, baseVertex, 0);
	}

	public function endPass() {
		Msg.v(enc, S.endEncoding);
		enc = Ptr.nil();
	}

	public function endFrame() {
		if (!drawable.isNull()) Msg.vPtr(cmd, S.presentDrawable, drawable);
		Msg.v(cmd, S.commit);
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
		for (p in pipelines) {
			Runtime.objc_release(p.state);
			Runtime.objc_release(p.depth);
		}
		for (o in shaders.concat(libraries).concat(buffers).concat(textures).concat(samplers))
			Runtime.objc_release(o);
		ObjC.release(readback);
		ObjC.release(target);
		ObjC.release(depth);
		Runtime.objc_release(pass);
		Runtime.objc_release(queue);
		#if hxmc.dev_host
		// (handing over: the layer keeps its device and its last frame for the next build)
		if (!layer.isNull() && !hxmc.dev.Hosted.handingOver) Msg.vPtr(layer, ObjC.sel("setDevice:"), Ptr.nil());
		#else
		if (!layer.isNull()) Msg.vPtr(layer, ObjC.sel("setDevice:"), Ptr.nil());
		#end
		Runtime.objc_release(device);
		LibC.free(scratch);
		LibC.free(clear);
		LibC.free(viewport);
		LibC.free(origin);
		LibC.free(size);
		LibC.free(region);
		LibC.free(uniforms);
	}
}

// a render pipeline state and its draw state
private class MtlPipeline {
	public final state:Ptr;
	public final depth:Ptr; // MTLDepthStencilState
	public final topology:Int;
	public final cull:Int;

	public function new(state:Ptr, depth:Ptr, d:PipelineDesc) {
		this.state = state;
		this.depth = depth;
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
	public static final setClearDepth = ObjC.sel("setClearDepth:");
	public static final setDepthStencilState = ObjC.sel("setDepthStencilState:");
	public static final drawIndexedPrimitives = ObjC.sel("drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:baseVertex:baseInstance:");
	public static final renderCommandEncoderWithDescriptor = ObjC.sel("renderCommandEncoderWithDescriptor:");
	public static final setViewport = ObjC.sel("setViewport:");
	public static final setFrontFacingWinding = ObjC.sel("setFrontFacingWinding:");
	public static final setRenderPipelineState = ObjC.sel("setRenderPipelineState:");
	public static final setCullMode = ObjC.sel("setCullMode:");
	public static final setVertexBuffer = ObjC.sel("setVertexBuffer:offset:atIndex:");
	public static final setVertexBytes = ObjC.sel("setVertexBytes:length:atIndex:");
	public static final setVertexTexture = ObjC.sel("setVertexTexture:atIndex:");
	public static final setFragmentTexture = ObjC.sel("setFragmentTexture:atIndex:");
	public static final setVertexSamplerState = ObjC.sel("setVertexSamplerState:atIndex:");
	public static final setFragmentSamplerState = ObjC.sel("setFragmentSamplerState:atIndex:");
	public static final setFragmentBytes = ObjC.sel("setFragmentBytes:length:atIndex:");
	public static final drawPrimitives = ObjC.sel("drawPrimitives:vertexStart:vertexCount:instanceCount:");
	public static final endEncoding = ObjC.sel("endEncoding");
	public static final presentDrawable = ObjC.sel("presentDrawable:");
	public static final commit = ObjC.sel("commit");
}
