package hxmc.gfx.gl;

import hxmc.gfx.egl.Egl;
import hxmc.gfx.*;
import hxmc.os.Surface;
import hxmc.unsafe.*;

// The GL back end: an OpenGL ES 3.0 context through EGL, on an X11 window's
// surface or, headless, on a pbuffer of Mesa's surfaceless platform. One
// vertex array object; vertex attributes are set at the first draw after
// a pipeline or vertex buffer change (ES 3.0 has no separate vertex formats).
class GLBackend {
	public final backend = Backend.GL;
	public var width(default, null) = 0;
	public var height(default, null) = 0;

	final surface:Surface;
	var display = Ptr.nil();
	var eglSurface = Ptr.nil();
	var context = Ptr.nil();
	// native memory for out-parameters, and the pixels of readPixels
	final scratch:Ptr<Int32>;
	var pixels = Ptr.nil();
	var pixelsSize = 0;

	// tables (handle = index + 1)
	final buffers:Array<Int> = [];
	final shaders:Array<Int> = [];
	final pipelines:Array<GLPipeline> = [];

	// draw state
	var pipeline:GLPipeline = null;
	final vbufs = [for (_ in 0...MAX_SLOTS) 0];
	final voffs = [for (_ in 0...MAX_SLOTS) 0];
	var dirty = true;
	var enabled = 0; // the attribute locations enabled, a mask

	static inline var MAX_SLOTS = 8;

	public function new(surface:Surface) {
		this.surface = surface;
		scratch = LibC.malloc((64 : Int64));
		var headless = surface.kind == Headless;
		if (headless)
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
				EGL.BLUE_SIZE, 8, EGL.ALPHA_SIZE, 8, EGL.NONE
			]);
			var config:Ptr<Ptr> = a.alloc(8);
			if (Egl.eglChooseConfig(display, attribs, config, 1, scratch) == 0 || scratch.value == 0) fail("no EGL config for GLES 3 with RGBA8");
			eglSurface = headless ? Egl.eglCreatePbufferSurface(display, config.value,
				ints(a, [EGL.WIDTH, surface.width, EGL.HEIGHT, surface.height, EGL.NONE])) : Egl.eglCreateWindowSurface(display, config.value,
					surface.handle, Ptr.nil());
			if (eglSurface.isNull()) fail("cannot create the EGL surface");
			context = Egl.eglCreateContext(display, config.value, Ptr.nil(), ints(a, [EGL.CONTEXT_MAJOR_VERSION, 3, EGL.CONTEXT_MINOR_VERSION, 0, EGL.NONE]));
			if (context.isNull()) fail("cannot create a GLES 3.0 context");
		});
		if (Egl.eglMakeCurrent(display, eglSurface, eglSurface, context) == 0) fail("eglMakeCurrent");
		var missing = GL.load(name -> Egl.eglGetProcAddress(name));
		if (missing != null) throw "hxmc.gfx: no GL function " + missing;
		GL.glGenVertexArrays(1, scratch);
		GL.glBindVertexArray(scratch.value);
		querySize();
	}

	function fail(what:String):Dynamic
		throw "hxmc.gfx: " + what + " (EGL error 0x" + StringTools.hex(Egl.eglGetError()) + ")";

	static function ints(a:Arena, xs:Array<Int>):Ptr<Int32> {
		var p:Ptr<Int32> = a.alloc(4 * xs.length);
		for (i in 0...xs.length)
			p[i] = xs[i];
		return p;
	}

	function querySize() {
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
		buffers.push(b);
		return buffers.length;
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
		if (d.layout.length > MAX_SLOTS) throw "hxmc.gfx: more than " + MAX_SLOTS + " vertex buffers";
		pipelines.push(new GLPipeline(p, d));
		return pipelines.length;
	}

	public function beginFrame():Bool {
		if (surface.kind != Headless) querySize();
		return true;
	}

	public function beginPass(p:PassDesc) {
		GL.glViewport(0, 0, width, height);
		var c = p.colors[0];
		if (c.load == Clear) {
			var k = c.clear;
			k == null ? GL.glClearColor(0, 0, 0, 1) : GL.glClearColor(k.r, k.g, k.b, k.a);
			GL.glClear(GL.COLOR_BUFFER_BIT);
		}
	}

	public function setPipeline(id:Int) {
		var p = pipelines[id - 1];
		if (p == pipeline) return;
		pipeline = p;
		GL.glUseProgram(p.program);
		if (p.cull == 0) GL.glDisable(GL.CULL_FACE) else {
			GL.glEnable(GL.CULL_FACE);
			GL.glCullFace(p.cull);
		}
		dirty = true;
	}

	public function setVertexBuffer(slot:Int, id:Int, offset:Int) {
		vbufs[slot] = buffers[id - 1];
		voffs[slot] = offset;
		dirty = true;
	}

	public function draw(vertices:Int, instances:Int, first:Int) {
		var p = pipeline;
		if (dirty) {
			var mask = 0;
			for (i in 0...p.locations.length) {
				var slot = p.slots[i], loc = p.locations[i];
				GL.glBindBuffer(GL.ARRAY_BUFFER, vbufs[slot]);
				GL.glVertexAttribPointer(loc, p.sizes[i], p.types[i], p.normalized[i], p.strides[slot], Ptr.ofI64(voffs[slot] + p.offsets[i]));
				if (enabled & (1 << loc) == 0) GL.glEnableVertexAttribArray(loc);
				mask |= 1 << loc;
			}
			for (loc in 0...16)
				if (enabled & ~mask & (1 << loc) != 0) GL.glDisableVertexAttribArray(loc);
			enabled = mask;
			dirty = false;
		}
		instances == 1 ? GL.glDrawArrays(p.topology, first, vertices) : GL.glDrawArraysInstanced(p.topology, first, vertices, instances);
	}

	public function endPass() {}

	public function endFrame() {
		if (surface.kind != Headless) Egl.eglSwapBuffers(display, eglSurface);
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
		Egl.eglMakeCurrent(display, Ptr.nil(), Ptr.nil(), Ptr.nil());
		Egl.eglDestroyContext(display, context);
		Egl.eglDestroySurface(display, eglSurface);
		Egl.eglTerminate(display);
		LibC.free(pixels);
		LibC.free(scratch);
	}
}

// a linked program and its vertex attributes, flattened for draw
private class GLPipeline {
	public final program:Int;
	public final topology:Int;
	public final cull:Int; // 0: none, else GL.FRONT or GL.BACK
	public final strides:Array<Int> = [];
	public final slots:Array<Int> = [];
	public final locations:Array<Int> = [];
	public final sizes:Array<Int> = [];
	public final types:Array<Int> = [];
	public final normalized:Array<Bool> = [];
	public final offsets:Array<Int> = [];

	public function new(program:Int, d:PipelineDesc) {
		this.program = program;
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
