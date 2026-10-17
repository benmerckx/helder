package hxmc.gfx.gl;

import hxmc.gfx.egl.Egl;
import hxmc.gfx.*;
import hxmc.os.Surface;
import hxmc.unsafe.*;

// The GL back end: an OpenGL ES 3.0 context through EGL, on an X11 window's
// surface or, headless, on a pbuffer of Mesa's surfaceless platform (on
// Android: the default display, the activity's ANativeWindow or a pbuffer;
// the GL functions from libGLESv3.so; when the system takes the window,
// Surface.lost, its EGL surface goes and the next frame makes one on the
// new window, the context and everything in it kept); in the
// browser (WebAssembly, without WebGPU: hxmc.gfx.Impl), a WebGL2 context on
// a canvas or an offscreen one (WebGL), the same GL calls going to
// imports. One vertex array object; vertex attributes are set at the first
// draw after a pipeline or vertex buffer change (ES 3.0 has no separate
// vertex formats). Uniform blocks and samplers are bound to their slots by
// name when a pipeline links (ShaderCode.bindings: ES 3.00 has no
// layout(binding)); setUniforms writes into the frame's uniform buffer, one
// of two (frames in flight), and binds the range (glBindBufferRange). The
// depth buffer is the default framebuffer's (24 bits); ES 3.0 has no base
// vertex, so drawIndexed's moves the vertex attributes' offsets instead.
// A texture at slot n is bound to texture unit n with its sampler object.
// The shader macro's fragment stages flip the fragment position with the
// target's height (u_target_height), set when a pipeline is.
class GLBackend {
	public final backend = Mem.os() == 3 ? Backend.WebGL2 : Backend.GL;
	public var width(default, null) = 0;
	public var height(default, null) = 0;

	final surface:Surface;
	var display = Ptr.nil();
	var eglSurface = Ptr.nil();
	var context = Ptr.nil();
	var config = Ptr.nil();
	// (Android) the native window eglSurface was made on
	var window = Ptr.nil();
	var web = 0; // the WebGL2 context
	// native memory for out-parameters, and the pixels of readPixels
	final scratch:Ptr<Int32>;
	var pixels = Ptr.nil();
	var pixelsSize = 0;

	// tables (handle = index + 1)
	final buffers:Array<Int> = [];
	final indexBuffers:Array<Bool> = [];
	final shaders:Array<Int> = [];
	final bindings:Array<Array<ShaderBinding>> = []; // each shader's
	final pipelines:Array<GLPipeline> = [];
	final textures:Array<Int> = [];
	final textureSizes:Array<Int> = []; // width, height
	final samplers:Array<Int> = [];

	// draw state
	var pipeline:GLPipeline = null;
	final vbufs = [for (_ in 0...MAX_SLOTS) 0];
	final voffs = [for (_ in 0...MAX_SLOTS) 0];
	var dirty = true;
	var base = 0; // the vertices' first: the attributes' offsets move by its stride
	var enabled = 0; // the attribute locations enabled, a mask
	var ibuf = 0; // the index buffer bound, the one set, its type (GL.UNSIGNED_*), its offset
	var ibufSet = 0;
	var itype = GL.UNSIGNED_SHORT;
	var ioffset = 0;
	var depthMask = true; // glDepthMask as it is
	final units = [for (_ in 0...16) 0]; // each texture unit's texture (setTexture)
	// the uniform rings (one per frame in flight: made at the first
	// setUniforms), the frame's, and the next offset into it
	final rings = [0, 0];
	var ring = 0;
	var cursor = 0;
	var uniformAlign = 256;

	static inline var MAX_SLOTS = 8;

	public function new(surface:Surface) {
		this.surface = surface;
		scratch = LibC.malloc((64 : Int64));
		if (Mem.os() == 3) {
			web = switch surface.kind {
				case Canvas: WebGL.context(surface.handle.toI64().toInt(), 0, 0);
				case Headless: WebGL.context(0, surface.width, surface.height);
				case k: throw "hxmc.gfx: WebGL2 renders to a canvas or headless, not to a surface of kind " + k;
			}
			if (web == 0) throw "hxmc.gfx: neither WebGPU nor WebGL2 is available";
			WebGL.make_current(web);
			GL.glGenVertexArrays(1, scratch);
			GL.glBindVertexArray(scratch.value);
			start();
			return;
		}
		var headless = surface.kind == Headless;
		if (Mem.target() >= 9)
			display = Egl.eglGetDisplay(Ptr.nil()); // (EGL_DEFAULT_DISPLAY)
		else if (headless)
			display = Egl.eglGetPlatformDisplay(EGL.PLATFORM_SURFACELESS_MESA, Ptr.nil(), Ptr.nil());
		else {
			display = Egl.eglGetPlatformDisplay(EGL.PLATFORM_X11_KHR, surface.display, Ptr.nil());
			if (display.isNull()) display = Egl.eglGetDisplay(surface.display);
		}
		if (display.isNull()) fail("no EGL display");
		if (Egl.eglInitialize(display, scratch, scratch.offset(1)) == 0) fail("eglInitialize");
		if (Egl.eglBindAPI(EGL.OPENGL_ES_API) == 0) fail("eglBindAPI");
		Arena.scoped(a -> {
			var attribs = ints(a, [
				EGL.SURFACE_TYPE, headless ? EGL.PBUFFER_BIT : EGL.WINDOW_BIT, EGL.RENDERABLE_TYPE, EGL.OPENGL_ES3_BIT, EGL.RED_SIZE, 8, EGL.GREEN_SIZE, 8,
				EGL.BLUE_SIZE, 8, EGL.ALPHA_SIZE, 8, EGL.DEPTH_SIZE, 24, EGL.NONE
			]);
			var configs:Ptr<Ptr> = a.alloc(8);
			if (Egl.eglChooseConfig(display, attribs, configs, 1, scratch) == 0 || scratch.value == 0) fail("no EGL config for GLES 3 with RGBA8 and a 24-bit depth buffer");
			config = configs.value;
			if (headless) {
				eglSurface = Egl.eglCreatePbufferSurface(display, config, ints(a, [EGL.WIDTH, surface.width, EGL.HEIGHT, surface.height, EGL.NONE]));
				if (eglSurface.isNull()) fail("cannot create the EGL surface");
			} else
				attach();
			context = Egl.eglCreateContext(display, config, Ptr.nil(), ints(a, [EGL.CONTEXT_MAJOR_VERSION, 3, EGL.CONTEXT_MINOR_VERSION, 0, EGL.NONE]));
			if (context.isNull()) fail("cannot create a GLES 3.0 context");
		});
		if (Egl.eglMakeCurrent(display, eglSurface, eglSurface, context) == 0) fail("eglMakeCurrent");
		// (Android: libGLESv3.so's own functions; eglGetProcAddress may know only extensions there)
		var gles = Mem.target() >= 9 ? Posix.dlopen(Mem.cstr("libGLESv3.so"), 2) : Ptr.nil();
		var missing = GL.load(name -> {
			var f = gles.isNull() ? Ptr.nil() : Posix.dlsym(gles, name);
			f.isNull() ? Egl.eglGetProcAddress(name) : f;
		});
		if (Mem.target() >= 9) {
			if (!headless) surface.lost = release;
		}
		if (missing != null) throw "hxmc.gfx: no GL function " + missing;
		GL.glGenVertexArrays(1, scratch);
		GL.glBindVertexArray(scratch.value);
		start();
	}

	// (the context is current)
	function start() {
		querySize();
		GL.glGetIntegerv(GL.UNIFORM_BUFFER_OFFSET_ALIGNMENT, scratch);
		if (scratch.value > uniformAlign) uniformAlign = scratch.value;
	}

	function fail(what:String):Dynamic
		throw "hxmc.gfx: " + what + (Mem.os() == 3 ? "" : " (EGL error 0x" + StringTools.hex(Egl.eglGetError()) + ")");

	static function ints(a:Arena, xs:Array<Int>):Ptr<Int32> {
		var p:Ptr<Int32> = a.alloc(4 * xs.length);
		for (i in 0...xs.length)
			p[i] = xs[i];
		return p;
	}

	function querySize() {
		if (Mem.os() == 3) {
			// (a canvas: its size now, which App's Resize events follow)
			width = surface.width;
			height = surface.height;
			return;
		}
		Egl.eglQuerySurface(display, eglSurface, EGL.WIDTH, scratch);
		width = scratch.value;
		Egl.eglQuerySurface(display, eglSurface, EGL.HEIGHT, scratch);
		height = scratch.value;
	}

	public function createBuffer(d:BufferDesc):Int {
		var target = d.usage == Index ? GL.ELEMENT_ARRAY_BUFFER : d.usage == Uniform ? GL.UNIFORM_BUFFER : GL.ARRAY_BUFFER;
		GL.glGenBuffers(1, scratch);
		var b = scratch.value;
		GL.glBindBuffer(target, b);
		var data = d.data, size = d.size;
		if (data != null && data.length < size) throw "hxmc.gfx: createBuffer: data has fewer than size bytes";
		// (a fast call: the Bytes cannot move during it)
		if (data == null) GL.glBufferData(target, size, Ptr.nil(), GL.DYNAMIC_DRAW) else GL.glBufferData(target, size, Mem.addr(data).add(8), GL.STATIC_DRAW);
		// (the vertex array's index buffer was this one: it is bound anew at the next drawIndexed)
		if (target == GL.ELEMENT_ARRAY_BUFFER) ibuf = -1;
		buffers.push(b);
		indexBuffers.push(d.usage == Index);
		return buffers.length;
	}

	public function writeBuffer(id:Int, offset:Int, data:haxe.io.Bytes, dataOffset:Int, size:Int) {
		// (an index buffer through its own target, as WebGL wants; the vertex
		// array's then is it, until the next drawIndexed binds the set one)
		var target = indexBuffers[id - 1] ? GL.ELEMENT_ARRAY_BUFFER : GL.ARRAY_BUFFER;
		GL.glBindBuffer(target, buffers[id - 1]);
		if (target == GL.ELEMENT_ARRAY_BUFFER) ibuf = -1;
		// (a fast call: the Bytes cannot move during it)
		GL.glBufferSubData(target, offset, size, Mem.addr(data).add(8 + dataOffset));
	}

	public function createTexture(d:TextureDesc):Int {
		GL.glGenTextures(1, scratch);
		var t = scratch.value;
		upload(t, d.width, d.height, d.data, true);
		textures.push(t);
		textureSizes.push(d.width);
		textureSizes.push(d.height);
		return textures.length;
	}

	public function writeTexture(id:Int, data:haxe.io.Bytes, x:Int, y:Int, w:Int, h:Int, dataOffset:Int) {
		var tw = textureSizes[2 * id - 2], th = textureSizes[2 * id - 1];
		if (w < 0) {
			w = tw;
			h = th;
		}
		if (x + w > tw || y + h > th) throw "hxmc.gfx: writeTexture: outside the texture";
		if (dataOffset + w * h * 4 > data.length) throw "hxmc.gfx: writeTexture: data has fewer than w * h * 4 bytes";
		GL.glActiveTexture(GL.TEXTURE0);
		GL.glBindTexture(GL.TEXTURE_2D, textures[id - 1]);
		GL.glPixelStorei(GL.UNPACK_ALIGNMENT, 4);
		// (a fast call: the Bytes cannot move during it)
		GL.glTexSubImage2D(GL.TEXTURE_2D, 0, x, y, w, h, GL.RGBA, GL.UNSIGNED_BYTE, Mem.addr(data).add(8 + dataOffset));
		GL.glBindTexture(GL.TEXTURE_2D, units[0]);
	}

	public function destroyBuffer(id:Int) {
		if (buffers[id - 1] == 0) return;
		scratch.value = buffers[id - 1];
		GL.glDeleteBuffers(1, scratch);
		buffers[id - 1] = 0;
	}

	public function destroyTexture(id:Int) {
		if (textures[id - 1] == 0) return;
		scratch.value = textures[id - 1];
		GL.glDeleteTextures(1, scratch);
		textures[id - 1] = 0;
	}

	// the texels (none: undefined) of a new texture or all of one, through unit
	// 0, whose texture is put back
	function upload(t:Int, w:Int, h:Int, data:Null<haxe.io.Bytes>, create:Bool) {
		GL.glActiveTexture(GL.TEXTURE0);
		GL.glBindTexture(GL.TEXTURE_2D, t);
		GL.glPixelStorei(GL.UNPACK_ALIGNMENT, 4);
		// (fast calls: the Bytes cannot move during them)
		if (create) {
			GL.glTexImage2D(GL.TEXTURE_2D, 0, GL.RGBA8, w, h, 0, GL.RGBA, GL.UNSIGNED_BYTE, data == null ? Ptr.nil() : Mem.addr(data).add(8));
			// (one level: complete with any sampler)
			GL.glTexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAX_LEVEL, 0);
			GL.glTexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.LINEAR);
		} else GL.glTexSubImage2D(GL.TEXTURE_2D, 0, 0, 0, w, h, GL.RGBA, GL.UNSIGNED_BYTE, Mem.addr(data).add(8));
		GL.glBindTexture(GL.TEXTURE_2D, units[0]);
	}

	public function createSampler(d:SamplerDesc):Int {
		GL.glGenSamplers(1, scratch);
		var s = scratch.value;
		var f = d.filter == Nearest ? GL.NEAREST : GL.LINEAR;
		var w = switch d.wrap {
			case null | Repeat: GL.REPEAT;
			case Clamp: GL.CLAMP_TO_EDGE;
			case Mirror: GL.MIRRORED_REPEAT;
		}
		GL.glSamplerParameteri(s, GL.TEXTURE_MIN_FILTER, f);
		GL.glSamplerParameteri(s, GL.TEXTURE_MAG_FILTER, f);
		GL.glSamplerParameteri(s, GL.TEXTURE_WRAP_S, w);
		GL.glSamplerParameteri(s, GL.TEXTURE_WRAP_T, w);
		samplers.push(s);
		return samplers.length;
	}

	public function createShader(d:ShaderDesc):Int {
		if (d.code.glsl == null) throw "hxmc.gfx: createShader: no GLSL source for the GL back end";
		var s = GL.glCreateShader(d.stage == Vertex ? GL.VERTEX_SHADER : GL.FRAGMENT_SHADER);
		Arena.scoped(a -> {
			var src:Ptr<Ptr> = a.alloc(8);
			src.value = a.cstring(d.code.glsl);
			GL.glShaderSource(s, 1, src, Ptr.nil());
		});
		GL.glCompileShader(s);
		GL.glGetShaderiv(s, GL.COMPILE_STATUS, scratch);
		if (scratch.value == 0) {
			var log = infoLog(s, false);
			GL.glDeleteShader(s);
			throw "hxmc.gfx: the shader does not compile:\n" + log;
		}
		shaders.push(s);
		bindings.push(d.code.bindings == null ? [] : d.code.bindings);
		return shaders.length;
	}

	function infoLog(o:Int, program:Bool):String {
		program ? GL.glGetProgramiv(o, GL.INFO_LOG_LENGTH, scratch) : GL.glGetShaderiv(o, GL.INFO_LOG_LENGTH, scratch);
		var n = scratch.value + 1;
		return Arena.scopedValue(a -> {
			var buf:Ptr<UInt8> = a.alloc(n);
			program ? GL.glGetProgramInfoLog(o, n, Ptr.nil(), buf) : GL.glGetShaderInfoLog(o, n, Ptr.nil(), buf);
			(buf : CString).toString();
		});
	}

	public function createPipeline(d:PipelineDesc):Int {
		var p = GL.glCreateProgram();
		GL.glAttachShader(p, shaders[d.vertex.id() - 1]);
		GL.glAttachShader(p, shaders[d.fragment.id() - 1]);
		GL.glLinkProgram(p);
		GL.glGetProgramiv(p, GL.LINK_STATUS, scratch);
		if (scratch.value == 0) {
			var log = infoLog(p, true);
			GL.glDeleteProgram(p);
			throw "hxmc.gfx: the pipeline does not link:\n" + log;
		}
		// the shaders' uniform blocks and samplers at their slots, by name
		GL.glUseProgram(p);
		for (b in bindings[d.vertex.id() - 1].concat(bindings[d.fragment.id() - 1]))
			Arena.scoped(a -> {
				var name = a.cstring(b.name);
				var block = b.kind == Uniform ? GL.glGetUniformBlockIndex(p, name) : GL.INVALID_INDEX;
				if (block != GL.INVALID_INDEX) GL.glUniformBlockBinding(p, block, b.slot) else {
					var loc = GL.glGetUniformLocation(p, name);
					if (loc >= 0) GL.glUniform1i(loc, b.slot);
				}
			});
		var heightLoc = Arena.scopedValue(a -> GL.glGetUniformLocation(p, a.cstring("u_target_height")));
		GL.glUseProgram(pipeline == null ? 0 : pipeline.program);
		if (d.layout.length > MAX_SLOTS) throw "hxmc.gfx: more than " + MAX_SLOTS + " vertex buffers";
		pipelines.push(new GLPipeline(p, heightLoc, d));
		return pipelines.length;
	}

	// (Android) the system takes the window: its EGL surface goes first
	function release() {
		// (Android only: no EGL import elsewhere, WebGL2's among them)
		if (Mem.target() < 9) return;
		if (eglSurface.isNull()) return;
		Egl.eglMakeCurrent(display, Ptr.nil(), Ptr.nil(), Ptr.nil());
		Egl.eglDestroySurface(display, eglSurface);
		eglSurface = Ptr.nil();
		window = Ptr.nil();
	}

	// an EGL surface on the window the Surface has now
	function attach() {
		// (not in the browser: no EGL import there)
		if (Mem.os() == 3) return;
		eglSurface = Egl.eglCreateWindowSurface(display, config, surface.handle, Ptr.nil());
		if (eglSurface.isNull()) fail("cannot create the EGL surface");
		window = surface.handle;
	}

	public function beginFrame():Bool {
		// (Android: a new window after a Resume, none while suspended; one
		// comparison of the target, folded elsewhere)
		if (Mem.target() >= 9 && surface.kind != Headless) {
			if (surface.handle != window) {
				release();
				if (surface.handle.isNull()) return false;
				attach();
				if (Egl.eglMakeCurrent(display, eglSurface, eglSurface, context) == 0) fail("eglMakeCurrent");
			}
			if (eglSurface.isNull()) return false;
		}
		ring ^= 1;
		cursor = 0;
		if (surface.kind != Headless) querySize();
		return true;
	}

	public function beginPass(p:PassDesc) {
		GL.glViewport(0, 0, width, height);
		var c = p.colors[0], mask = 0;
		if (c.load != Load) {
			var k = c.clear;
			k == null ? GL.glClearColor(0, 0, 0, 1) : GL.glClearColor(k.r, k.g, k.b, k.a);
			mask |= GL.COLOR_BUFFER_BIT;
		}
		var d = p.depth;
		if (d != null && d.load != Load) {
			GL.glClearDepthf(d.clear == null ? 1 : d.clear);
			// (the mask applies to clears too)
			if (!depthMask) GL.glDepthMask(depthMask = true);
			mask |= GL.DEPTH_BUFFER_BIT;
		}
		if (mask != 0) GL.glClear(mask);
		pipeline = null;
	}

	public function setPipeline(id:Int) {
		var p = pipelines[id - 1];
		if (p == pipeline) return;
		pipeline = p;
		GL.glUseProgram(p.program);
		// (the fragment position's flip: the shader macro's GLSL)
		if (p.heightLoc >= 0 && p.height != height) {
			p.height = height;
			GL.glUniform1f(p.heightLoc, height);
		}
		if (p.cull == 0) GL.glDisable(GL.CULL_FACE) else {
			GL.glEnable(GL.CULL_FACE);
			GL.glCullFace(p.cull);
		}
		if (p.depthFunc == 0) GL.glDisable(GL.DEPTH_TEST) else {
			GL.glEnable(GL.DEPTH_TEST);
			GL.glDepthFunc(p.depthFunc);
		}
		if (p.depthWrite != depthMask) GL.glDepthMask(depthMask = p.depthWrite);
		if (p.blend == Opaque) GL.glDisable(GL.BLEND) else {
			GL.glEnable(GL.BLEND);
			GL.glBlendEquation(GL.FUNC_ADD);
			switch p.blend {
				case Alpha: GL.glBlendFuncSeparate(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA, GL.ONE, GL.ONE_MINUS_SRC_ALPHA);
				case Additive: GL.glBlendFuncSeparate(GL.SRC_ALPHA, GL.ONE, GL.ONE, GL.ONE);
				case _: GL.glBlendFuncSeparate(GL.ONE, GL.ONE_MINUS_SRC_ALPHA, GL.ONE, GL.ONE_MINUS_SRC_ALPHA);
			}
		}
		dirty = true;
	}

	public function setVertexBuffer(slot:Int, id:Int, offset:Int) {
		vbufs[slot] = buffers[id - 1];
		voffs[slot] = offset;
		dirty = true;
	}

	public function setUniforms(slot:Int, data:haxe.io.Bytes, offset:Int, size:Int) {
		if (offset < 0 || size < 0 || offset + size > data.length) throw "hxmc.gfx: setUniforms: outside the data";
		var n = (size + uniformAlign - 1) & ~(uniformAlign - 1);
		if (cursor + n > Encoder.UNIFORM_RING) throw "hxmc.gfx: setUniforms: more than " + Encoder.UNIFORM_RING + " bytes of uniforms in a frame";
		if (rings[ring] == 0) {
			GL.glGenBuffers(1, scratch);
			rings[ring] = scratch.value;
			GL.glBindBuffer(GL.UNIFORM_BUFFER, rings[ring]);
			GL.glBufferData(GL.UNIFORM_BUFFER, Encoder.UNIFORM_RING, Ptr.nil(), GL.STREAM_DRAW);
		} else GL.glBindBuffer(GL.UNIFORM_BUFFER, rings[ring]);
		// (a fast call: the Bytes cannot move during it; the range: whole 16-byte rows)
		GL.glBufferSubData(GL.UNIFORM_BUFFER, cursor, size, Mem.addr(data).add(8 + offset));
		GL.glBindBufferRange(GL.UNIFORM_BUFFER, slot, rings[ring], cursor, (size + 15) & ~15);
		cursor += n;
	}

	public function draw(vertices:Int, instances:Int, first:Int) {
		attributes(0);
		instances == 1 ? GL.glDrawArrays(pipeline.topology, first, vertices) : GL.glDrawArraysInstanced(pipeline.topology, first, vertices, instances);
	}

	public function setTexture(slot:Int, texture:Int, sampler:Int) {
		GL.glActiveTexture(GL.TEXTURE0 + slot);
		GL.glBindTexture(GL.TEXTURE_2D, units[slot] = textures[texture - 1]);
		GL.glBindSampler(slot, samplers[sampler - 1]);
	}

	public function setIndexBuffer(id:Int, format:IndexFormat, offset:Int) {
		ibufSet = buffers[id - 1];
		itype = format == UInt16 ? GL.UNSIGNED_SHORT : GL.UNSIGNED_INT;
		ioffset = offset;
	}

	public function drawIndexed(count:Int, instances:Int, first:Int, baseVertex:Int) {
		attributes(baseVertex);
		if (ibuf != ibufSet) GL.glBindBuffer(GL.ELEMENT_ARRAY_BUFFER, ibuf = ibufSet);
		var at:Int = ioffset + first * (itype == GL.UNSIGNED_SHORT ? 2 : 4);
		instances == 1 ? GL.glDrawElements(pipeline.topology, count, itype, Ptr.ofI64(at)) : GL.glDrawElementsInstanced(pipeline.topology, count, itype, Ptr.ofI64(at), instances);
	}

	// the vertex attributes, when the pipeline, a vertex buffer or the base vertex changed
	function attributes(first:Int) {
		if (!dirty && first == base) return;
		var p = pipeline, mask = 0;
		for (i in 0...p.locations.length) {
			var slot = p.slots[i], loc = p.locations[i];
			GL.glBindBuffer(GL.ARRAY_BUFFER, vbufs[slot]);
			GL.glVertexAttribPointer(loc, p.sizes[i], p.types[i], p.normalized[i], p.strides[slot], Ptr.ofI64(voffs[slot] + first * p.strides[slot] + p.offsets[i]));
			if (enabled & (1 << loc) == 0) GL.glEnableVertexAttribArray(loc);
			mask |= 1 << loc;
		}
		for (loc in 0...16)
			if (enabled & ~mask & (1 << loc) != 0) GL.glDisableVertexAttribArray(loc);
		enabled = mask;
		base = first;
		dirty = false;
	}

	public function endPass() {}

	public function endFrame() {
		if (Mem.os() == 3) WebGL.swap(web) else if (surface.kind != Headless && !eglSurface.isNull()) Egl.eglSwapBuffers(display, eglSurface);
	}

	public function readPixels(dst:haxe.io.Bytes) {
		var row = width * 4, size = row * height;
		if (dst.length < size) throw "hxmc.gfx: readPixels: " + size + " bytes needed";
		if (pixelsSize < size) {
			LibC.free(pixels);
			pixels = LibC.malloc((size : Int64));
			pixelsSize = size;
		}
		GL.glPixelStorei(GL.PACK_ALIGNMENT, 1);
		GL.glReadPixels(0, 0, width, height, GL.RGBA, GL.UNSIGNED_BYTE, pixels);
		// GL's rows go bottom to top
		for (y in 0...height)
			LibC.memcpy(Mem.addr(dst).add(8 + y * row), pixels.add((height - 1 - y) * row), (row : Int64));
	}

	public function dispose() {
		for (r in rings)
			if (r != 0) {
				scratch.value = r;
				GL.glDeleteBuffers(1, scratch);
			}
		if (Mem.os() == 3) WebGL.release(web) else {
			Egl.eglMakeCurrent(display, Ptr.nil(), Ptr.nil(), Ptr.nil());
			Egl.eglDestroyContext(display, context);
			if (!eglSurface.isNull()) Egl.eglDestroySurface(display, eglSurface);
			if (Mem.target() >= 9) surface.lost = null;
			Egl.eglTerminate(display);
		}
		LibC.free(pixels);
		LibC.free(scratch);
	}
}

// a linked program and its vertex attributes, flattened for draw
private class GLPipeline {
	public final program:Int;
	public final heightLoc:Int; // u_target_height (-1: none), as set
	public var height = -1;
	public final topology:Int;
	public final cull:Int; // 0: none, else GL.FRONT or GL.BACK
	public final depthFunc:Int; // 0: no depth test, else GL.NEVER + Compare
	public final depthWrite:Bool;
	public final blend:Blend;
	public final strides:Array<Int> = [];
	public final slots:Array<Int> = [];
	public final locations:Array<Int> = [];
	public final sizes:Array<Int> = [];
	public final types:Array<Int> = [];
	public final normalized:Array<Bool> = [];
	public final offsets:Array<Int> = [];

	public function new(program:Int, heightLoc:Int, d:PipelineDesc) {
		this.program = program;
		this.heightLoc = heightLoc;
		topology = switch d.topology {
			case null | Triangles: GL.TRIANGLES;
			case TriangleStrip: GL.TRIANGLE_STRIP;
			case Lines: GL.LINES;
			case Points: GL.POINTS;
		}
		cull = switch d.cull {
			case null | None: 0;
			case Front: GL.FRONT;
			case Back: GL.BACK;
		}
		depthWrite = d.depthWrite == true;
		var c:Compare = d.depthCompare == null ? Always : d.depthCompare;
		// (GL tests nothing and writes nothing without the depth test)
		depthFunc = c == Always && !depthWrite ? 0 : GL.NEVER + (cast c : Int);
		blend = d.blend == null ? Opaque : d.blend;
		for (slot in 0...d.layout.length) {
			var l = d.layout[slot];
			strides.push(l.stride);
			for (a in l.attributes) {
				slots.push(slot);
				locations.push(a.location);
				offsets.push(a.offset);
				sizes.push(switch a.format {
					case Float1: 1;
					case Float2: 2;
					case Float3: 3;
					case Float4 | UByte4Norm: 4;
				});
				types.push(a.format == UByte4Norm ? GL.UNSIGNED_BYTE : GL.FLOAT);
				normalized.push(a.format == UByte4Norm);
			}
		}
	}
}
