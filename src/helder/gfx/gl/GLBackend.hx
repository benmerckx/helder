package helder.gfx.gl;

import helder.gfx.egl.Egl;
import helder.gfx.*;
import helder.os.Surface;
import hxmc.unsafe.*;

// The GL back end: an OpenGL ES 3.0 context through EGL, on an X11 window's
// surface or, headless, on a pbuffer of Mesa's surfaceless platform (on
// Android: the default display, the activity's ANativeWindow or a pbuffer;
// the GL functions from libGLESv3.so; when the system takes the window,
// Surface.lost, its EGL surface goes and the next frame makes one on the
// new window, the context and everything in it kept); in the
// browser (WebAssembly, without WebGPU: helder.gfx.Impl), a WebGL2 context on
// a canvas or an offscreen one (WebGL), the same GL calls going to
// imports. One vertex array object; vertex attributes are set at the first
// draw after a pipeline or vertex buffer change (ES 3.0 has no separate
// vertex formats). Uniform blocks and samplers are bound to their slots by
// name when a pipeline links (ShaderCode.bindings: ES 3.00 has no
// layout(binding)); setUniforms writes into the frame's uniform buffer, one
// of two (frames in flight), and binds the range (glBindBufferRange). The
// depth buffer is the default framebuffer's (24 bits); ES 3.0 has no base
// vertex, so drawIndexed's moves the vertex attributes' offsets instead
// (not an instance buffer's: its attributes have divisor 1).
// A texture at slot n is bound to texture unit n with its sampler object.
// The shader macro's stages flip the fragment position with the frame's
// height and, in a pass into a texture, the position, so that the texture's
// first row is the image's top as elsewhere (u_target, set when a pipeline
// is; the front faces turn clockwise there). A pass into a texture renders
// into one framebuffer object, attached anew when the textures change.
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
	final infos:Array<TextureInfo> = [];
	final samplers:Array<Int> = [];

	// draw state
	var pipeline:GLPipeline = null;
	final vbufs = [for (_ in 0...MAX_SLOTS) 0];
	final voffs = [for (_ in 0...MAX_SLOTS) 0];
	var dirty = true;
	var base = 0; // the vertices' first: the attributes' offsets move by its stride
	var enabled = 0; // the attribute locations enabled, a mask
	var divided = 0; // the attribute locations with divisor 1 (per instance), a mask
	var ibuf = 0; // the index buffer bound, the one set, its type (GL.UNSIGNED_*), its offset
	var ibufSet = 0;
	var itype = GL.UNSIGNED_SHORT;
	var ioffset = 0;
	var depthMask = true; // glDepthMask as it is
	final units = [for (_ in 0...16) 0]; // each texture unit's texture (setTexture)
	// passes into textures: the framebuffer object (made at the first), its
	// attachments (texture names), the framebuffer bound; the pass's flip
	// (rendering upside down into a texture, front faces clockwise)
	var fbo = 0;
	var fboColor = 0;
	var fboDepth = 0;
	var framebuffer = 0;
	var flipped = false;
	var frontCW = false;
	// the uniform rings (one per frame in flight: made at the first
	// setUniforms), the frame's, and the next offset into it
	final rings = [0, 0];
	var ring = 0;
	var cursor = 0;
	var uniformAlign = 256;

	static inline var MAX_SLOTS = 8;
	#if hxmc.dev
	var vao = 0;
	#end
	#if hxmc.dev_host
	// the context is the host's (helder.dev.Hosted): made by an earlier build
	var hostKept = false;
	#end
	#if hxmc.dev

	// (hxmc dev) every object this back end made deleted: a build swapped out
	// leaves a context the next one takes over (the browser's canvas, a dev host's window)
	function deleteAll() {
		GL.glBindVertexArray(0);
		GL.glUseProgram(0);
		GL.glBindFramebuffer(GL.FRAMEBUFFER, 0);
		for (i in 0...buffers.length)
			destroyBuffer(i + 1);
		for (i in 0...textures.length)
			destroyTexture(i + 1);
		for (s in samplers) {
			scratch.value = s;
			GL.glDeleteSamplers(1, scratch);
		}
		for (p in pipelines)
			GL.glDeleteProgram(p.program);
		for (s in shaders)
			GL.glDeleteShader(s);
		if (vao != 0) {
			scratch.value = vao;
			GL.glDeleteVertexArrays(1, scratch);
		}
		samplers.resize(0);
		pipelines.resize(0);
		shaders.resize(0);
		vao = 0;
	}
	#end

	public function new(surface:Surface) {
		this.surface = surface;
		scratch = LibC.malloc((64 : Int64));
		if (Mem.os() == 3) {
			web = switch surface.kind {
				case Canvas: WebGL.context(surface.handle.toI64().toInt(), 0, 0);
				case Headless: WebGL.context(0, surface.width, surface.height);
				case k: throw "helder.gfx: WebGL2 renders to a canvas or headless, not to a surface of kind " + k;
			}
			if (web == 0) throw "helder.gfx: neither WebGPU nor WebGL2 is available";
			WebGL.make_current(web);
			GL.glGenVertexArrays(1, scratch);
			GL.glBindVertexArray(scratch.value);
			#if hxmc.dev
			vao = scratch.value;
			#end
			start();
			return;
		}
		var headless = surface.kind == Headless;
		#if hxmc.dev_host
		// (hxmc dev's host: the context and its surface on the host's window, as the last build left them)
		if (!headless && helder.dev.Hosted.hosted() && !helder.dev.Hosted.get(helder.dev.Hosted.EGL_CONTEXT).isNull()) {
			display = helder.dev.Hosted.get(helder.dev.Hosted.EGL_DISPLAY);
			config = helder.dev.Hosted.get(helder.dev.Hosted.EGL_CONFIG);
			context = helder.dev.Hosted.get(helder.dev.Hosted.EGL_CONTEXT);
			eglSurface = helder.dev.Hosted.get(helder.dev.Hosted.EGL_SURFACE);
			window = surface.handle;
			hostKept = true;
		}
		if (!hostKept) {
		#end
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
		#if hxmc.dev_host
		if (!headless && helder.dev.Hosted.hosted()) {
			helder.dev.Hosted.set(helder.dev.Hosted.EGL_DISPLAY, display);
			helder.dev.Hosted.set(helder.dev.Hosted.EGL_CONFIG, config);
			helder.dev.Hosted.set(helder.dev.Hosted.EGL_CONTEXT, context);
			helder.dev.Hosted.set(helder.dev.Hosted.EGL_SURFACE, eglSurface);
		}
		}
		#end
		if (Egl.eglMakeCurrent(display, eglSurface, eglSurface, context) == 0) fail("eglMakeCurrent");
		// (Android: libGLESv3.so's own functions; eglGetProcAddress may know only extensions there)
		var gles = Mem.target() >= 9 ? Posix.dlopen(Mem.cstr("libGLESv3.so"), 2) : Ptr.nil();
		var missing = GL.load(name -> {
			var f = Ptr.nil();
			// (Android only: no dlsym where the browser is GL's)
			if (Mem.target() >= 9) if (!gles.isNull()) f = Posix.dlsym(gles, name);
			f.isNull() ? Egl.eglGetProcAddress(name) : f;
		});
		if (Mem.target() >= 9) {
			if (!headless) surface.lost = release;
		}
		if (missing != null) throw "helder.gfx: no GL function " + missing;
		GL.glGenVertexArrays(1, scratch);
		GL.glBindVertexArray(scratch.value);
		#if hxmc.dev
		vao = scratch.value;
		#end
		start();
	}

	// (the context is current)
	function start() {
		querySize();
		GL.glGetIntegerv(GL.UNIFORM_BUFFER_OFFSET_ALIGNMENT, scratch);
		if (scratch.value > uniformAlign) uniformAlign = scratch.value;
	}

	function fail(what:String):Dynamic
		throw "helder.gfx: " + what + (Mem.os() == 3 ? "" : " (EGL error 0x" + StringTools.hex(Egl.eglGetError()) + ")");

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
		if (data != null && data.length < size) throw "helder.gfx: createBuffer: data has fewer than size bytes";
		// (a fast call: the Bytes cannot move during it)
		if (data == null) GL.glBufferData(target, size, Ptr.nil(), GL.DYNAMIC_DRAW) else GL.glBufferData(target, size, BytesPtr.of(data, 0, size), GL.STATIC_DRAW);
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
		GL.glBufferSubData(target, offset, size, BytesPtr.of(data, dataOffset, size));
	}

	public function createTexture(d:TextureDesc):Int {
		var info = TextureInfo.of(d);
		GL.glGenTextures(1, scratch);
		var t = scratch.value;
		textures.push(t);
		infos.push(info);
		GL.glActiveTexture(GL.TEXTURE0);
		GL.glBindTexture(GL.TEXTURE_2D, t);
		// (immutable storage: every level, complete with any sampler)
		GL.glTexStorage2D(GL.TEXTURE_2D, info.levels, switch info.format {
			case RGBA8: GL.RGBA8;
			case RGBA8Srgb: GL.SRGB8_ALPHA8;
			case R8: GL.R8;
			case RG8: GL.RG8;
			case RGBA16F: GL.RGBA16F;
			case R32F: GL.R32F;
			case Depth16: GL.DEPTH_COMPONENT16;
			case Depth32F: GL.DEPTH_COMPONENT32F;
		}, info.width, info.height);
		GL.glBindTexture(GL.TEXTURE_2D, units[0]);
		if (d.data != null) writeTexture(textures.length, d.data, 0, 0, -1, -1, 0, 0);
		return textures.length;
	}

	public function writeTexture(id:Int, data:haxe.io.Bytes, x:Int, y:Int, w:Int, h:Int, dataOffset:Int, level:Int) {
		var info = infos[id - 1];
		info.checkWrite(data, x, y, w, h, dataOffset, level);
		var f = info.format;
		GL.glActiveTexture(GL.TEXTURE0);
		GL.glBindTexture(GL.TEXTURE_2D, textures[id - 1]);
		GL.glPixelStorei(GL.UNPACK_ALIGNMENT, 1);
		// (a fast call: the Bytes cannot move during it)
		GL.glTexSubImage2D(GL.TEXTURE_2D, level, x, y, info.w, info.h, f == R8 ? GL.RED : f == RG8 ? GL.RG : f == R32F ? GL.RED : GL.RGBA,
			f == RGBA16F ? GL.HALF_FLOAT : f == R32F ? GL.FLOAT : GL.UNSIGNED_BYTE, BytesPtr.of(data, dataOffset, data.length - dataOffset));
		GL.glBindTexture(GL.TEXTURE_2D, units[0]);
	}

	public function generateMips(id:Int) {
		infos[id - 1].checkMips();
		GL.glActiveTexture(GL.TEXTURE0);
		GL.glBindTexture(GL.TEXTURE_2D, textures[id - 1]);
		GL.glGenerateMipmap(GL.TEXTURE_2D);
		GL.glBindTexture(GL.TEXTURE_2D, units[0]);
	}

	public function destroyBuffer(id:Int) {
		if (buffers[id - 1] == 0) return;
		scratch.value = buffers[id - 1];
		GL.glDeleteBuffers(1, scratch);
		buffers[id - 1] = 0;
	}

	public function destroyTexture(id:Int) {
		var t = textures[id - 1];
		if (t == 0) return;
		// (a name GL may give again: not the framebuffer's attachment any more)
		if (t == fboColor) fboColor = -1;
		if (t == fboDepth) fboDepth = -1;
		scratch.value = t;
		GL.glDeleteTextures(1, scratch);
		textures[id - 1] = 0;
	}

	public function createSampler(d:SamplerDesc):Int {
		GL.glGenSamplers(1, scratch);
		var s = scratch.value;
		var nearest = d.filter == Nearest, mip = d.mipFilter;
		var f = nearest ? GL.NEAREST : GL.LINEAR;
		var min = mip == null ? f : GL.NEAREST_MIPMAP_NEAREST + (nearest ? 0 : 1) + (mip == Nearest ? 0 : 2);
		var w = switch d.wrap {
			case null | Repeat: GL.REPEAT;
			case Clamp: GL.CLAMP_TO_EDGE;
			case Mirror: GL.MIRRORED_REPEAT;
		}
		GL.glSamplerParameteri(s, GL.TEXTURE_MIN_FILTER, min);
		GL.glSamplerParameteri(s, GL.TEXTURE_MAG_FILTER, f);
		GL.glSamplerParameteri(s, GL.TEXTURE_WRAP_S, w);
		GL.glSamplerParameteri(s, GL.TEXTURE_WRAP_T, w);
		samplers.push(s);
		return samplers.length;
	}

	public function createShader(d:ShaderDesc):Int {
		if (d.code.glsl == null) throw "helder.gfx: createShader: no GLSL source for the GL back end";
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
			throw "helder.gfx: the shader does not compile:\n" + log;
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
			throw "helder.gfx: the pipeline does not link:\n" + log;
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
		var targetLoc = Arena.scopedValue(a -> GL.glGetUniformLocation(p, a.cstring("u_target")));
		GL.glUseProgram(pipeline == null ? 0 : pipeline.program);
		if (d.layout.length > MAX_SLOTS) throw "helder.gfx: more than " + MAX_SLOTS + " vertex buffers";
		pipelines.push(new GLPipeline(p, targetLoc, d));
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
		#if hxmc.dev_host
		if (helder.dev.Hosted.hosted() && helder.dev.Hosted.get(helder.dev.Hosted.EGL_CONTEXT) == context) helder.dev.Hosted.set(helder.dev.Hosted.EGL_SURFACE, Ptr.nil());
		#end
	}

	// an EGL surface on the window the Surface has now
	function attach() {
		// (not in the browser: no EGL import there)
		if (Mem.os() == 3) return;
		eglSurface = Egl.eglCreateWindowSurface(display, config, surface.handle, Ptr.nil());
		if (eglSurface.isNull()) fail("cannot create the EGL surface");
		window = surface.handle;
		#if hxmc.dev_host
		if (helder.dev.Hosted.hosted() && helder.dev.Hosted.get(helder.dev.Hosted.EGL_CONTEXT) == context) helder.dev.Hosted.set(helder.dev.Hosted.EGL_SURFACE, eglSurface);
		#end
	}

	public function beginFrame():Bool {
		// (Android: a new window after a Resume, none while suspended; the
		// target's comparison alone, folded elsewhere)
		if (Mem.target() >= 9) if (surface.kind != Headless) {
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
		var c = p.colors[0], d = p.depth, mask = 0;
		if (c.texture == null) {
			if (framebuffer != 0) GL.glBindFramebuffer(GL.FRAMEBUFFER, framebuffer = 0);
			GL.glViewport(0, 0, width, height);
			flipped = false;
		} else {
			// (one framebuffer object, its attachments changed when the pass's textures do)
			var info = infos[c.texture.id() - 1];
			info.checkPass(d);
			if (fbo == 0) {
				GL.glGenFramebuffers(1, scratch);
				fbo = scratch.value;
			}
			if (framebuffer != fbo) GL.glBindFramebuffer(GL.FRAMEBUFFER, framebuffer = fbo);
			var color = textures[c.texture.id() - 1], depth = d == null ? 0 : textures[d.texture.id() - 1];
			if (color != fboColor || depth != fboDepth) {
				GL.glFramebufferTexture2D(GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.TEXTURE_2D, fboColor = color, 0);
				GL.glFramebufferTexture2D(GL.FRAMEBUFFER, GL.DEPTH_ATTACHMENT, GL.TEXTURE_2D, fboDepth = depth, 0);
				var status = GL.glCheckFramebufferStatus(GL.FRAMEBUFFER);
				if (status != GL.FRAMEBUFFER_COMPLETE) throw "helder.gfx: beginPass: the textures are no complete framebuffer (status " + status + ")";
			}
			GL.glViewport(0, 0, info.width, info.height);
			flipped = true;
		}
		// (upside down into a texture: its faces turn clockwise)
		if (flipped != frontCW) GL.glFrontFace((frontCW = flipped) ? GL.CW : GL.CCW);
		if (c.load != Load) {
			var k = c.clear;
			k == null ? GL.glClearColor(0, 0, 0, 1) : GL.glClearColor(k.r, k.g, k.b, k.a);
			mask |= GL.COLOR_BUFFER_BIT;
		}
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
		// (the flips of the shader macro's GLSL: the fragment position's in
		// the frame, the position's into a texture)
		var target = flipped ? -1 : height;
		if (p.targetLoc >= 0 && p.target != target) {
			p.target = target;
			flipped ? GL.glUniform2f(p.targetLoc, 0, 1) : GL.glUniform2f(p.targetLoc, height, -1);
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
		if (offset < 0 || size < 0 || offset + size > data.length) throw "helder.gfx: setUniforms: outside the data";
		var n = (size + uniformAlign - 1) & ~(uniformAlign - 1);
		if (cursor + n > Encoder.UNIFORM_RING) throw "helder.gfx: setUniforms: more than " + Encoder.UNIFORM_RING + " bytes of uniforms in a frame";
		if (rings[ring] == 0) {
			GL.glGenBuffers(1, scratch);
			rings[ring] = scratch.value;
			GL.glBindBuffer(GL.UNIFORM_BUFFER, rings[ring]);
			GL.glBufferData(GL.UNIFORM_BUFFER, Encoder.UNIFORM_RING, Ptr.nil(), GL.STREAM_DRAW);
		} else GL.glBindBuffer(GL.UNIFORM_BUFFER, rings[ring]);
		// (a fast call: the Bytes cannot move during it; the range: whole 16-byte rows)
		GL.glBufferSubData(GL.UNIFORM_BUFFER, cursor, size, BytesPtr.of(data, offset, size));
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
			var instanced = p.instanced & (1 << slot) != 0;
			var at:Int = voffs[slot] + (instanced ? 0 : first * p.strides[slot]) + p.offsets[i];
			GL.glVertexAttribPointer(loc, p.sizes[i], p.types[i], p.normalized[i], p.strides[slot], Ptr.ofI64(at));
			if (enabled & (1 << loc) == 0) GL.glEnableVertexAttribArray(loc);
			if ((divided & (1 << loc) != 0) != instanced) {
				GL.glVertexAttribDivisor(loc, instanced ? 1 : 0);
				divided ^= 1 << loc;
			}
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
		if (dst.length < size) throw "helder.gfx: readPixels: " + size + " bytes needed";
		if (pixelsSize < size) {
			LibC.free(pixels);
			pixels = LibC.malloc((size : Int64));
			pixelsSize = size;
		}
		if (framebuffer != 0) GL.glBindFramebuffer(GL.FRAMEBUFFER, framebuffer = 0);
		GL.glPixelStorei(GL.PACK_ALIGNMENT, 1);
		GL.glReadPixels(0, 0, width, height, GL.RGBA, GL.UNSIGNED_BYTE, pixels);
		// GL's rows go bottom to top
		for (y in 0...height)
			BytesPtr.copyIn(dst, y * row, pixels.add((height - 1 - y) * row), row);
	}

	public function dispose() {
		#if hxmc.dev
		deleteAll();
		#end
		if (fbo != 0) {
			scratch.value = fbo;
			GL.glDeleteFramebuffers(1, scratch);
		}
		for (r in rings)
			if (r != 0) {
				scratch.value = r;
				GL.glDeleteBuffers(1, scratch);
			}
		#if hxmc.dev_host
		// (handing over: the context, its surface and the display left to the next build, not current on this thread)
		if (Mem.os() != 3 && helder.dev.Hosted.hosted() && helder.dev.Hosted.get(helder.dev.Hosted.EGL_CONTEXT) == context && !context.isNull()) {
			if (helder.dev.Hosted.handingOver) {
				Egl.eglMakeCurrent(display, Ptr.nil(), Ptr.nil(), Ptr.nil());
				LibC.free(pixels);
				LibC.free(scratch);
				return;
			}
			helder.dev.Hosted.set(helder.dev.Hosted.EGL_CONTEXT, Ptr.nil());
		}
		#end
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
	public final targetLoc:Int; // u_target (-1: none), as set: the frame's height, or -1 (a texture)
	public var target = -2;
	public final topology:Int;
	public final cull:Int; // 0: none, else GL.FRONT or GL.BACK
	public final depthFunc:Int; // 0: no depth test, else GL.NEVER + Compare
	public final depthWrite:Bool;
	public final blend:Blend;
	public final strides:Array<Int> = [];
	public var instanced = 0; // the slots stepping per instance, a mask
	public final slots:Array<Int> = [];
	public final locations:Array<Int> = [];
	public final sizes:Array<Int> = [];
	public final types:Array<Int> = [];
	public final normalized:Array<Bool> = [];
	public final offsets:Array<Int> = [];

	public function new(program:Int, targetLoc:Int, d:PipelineDesc) {
		this.program = program;
		this.targetLoc = targetLoc;
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
			if (l.step == Instance) instanced |= 1 << slot;
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
