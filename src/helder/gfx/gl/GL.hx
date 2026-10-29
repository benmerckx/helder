package helder.gfx.gl;

import hxmc.unsafe.*;

// OpenGL ES 3.0 (the subset GL 3.3 core shares): the entry points the GL
// back end calls, through pointers from GetProcAddress (Loader: GL.load),
// or on WebAssembly imports that call WebGL2 (src/helder/gfx/imports.mjs:
// object names are handles of its table, memory is the module's; no
// glGetString there). GLenum, GLuint, GLint, GLsizei are Int, GLsizeiptr
// and GLintptr Int64, GLboolean Bool.
@:build(helder.gfx.gl.Loader.build())
class GL {
	public static inline var NO_ERROR = 0;
	public static inline var COLOR_BUFFER_BIT = 0x4000;
	public static inline var DEPTH_BUFFER_BIT = 0x0100;
	public static inline var TRIANGLES = 0x0004;
	public static inline var TRIANGLE_STRIP = 0x0005;
	public static inline var LINES = 0x0001;
	public static inline var POINTS = 0x0000;
	public static inline var ARRAY_BUFFER = 0x8892;
	public static inline var ELEMENT_ARRAY_BUFFER = 0x8893;
	public static inline var UNIFORM_BUFFER = 0x8A11;
	public static inline var STATIC_DRAW = 0x88E4;
	public static inline var DYNAMIC_DRAW = 0x88E8;
	public static inline var STREAM_DRAW = 0x88E0;
	public static inline var VERTEX_SHADER = 0x8B31;
	public static inline var FRAGMENT_SHADER = 0x8B30;
	public static inline var COMPILE_STATUS = 0x8B81;
	public static inline var LINK_STATUS = 0x8B82;
	public static inline var INFO_LOG_LENGTH = 0x8B84;
	public static inline var FLOAT = 0x1406;
	public static inline var UNSIGNED_BYTE = 0x1401;
	public static inline var RGBA = 0x1908;
	public static inline var PACK_ALIGNMENT = 0x0D05;
	public static inline var CULL_FACE = 0x0B44;
	public static inline var FRONT = 0x0404;
	public static inline var BACK = 0x0405;
	public static inline var CCW = 0x0901;
	public static inline var VERSION = 0x1F02;
	public static inline var RENDERER = 0x1F01;
	public static inline var UNSIGNED_SHORT = 0x1403;
	public static inline var UNSIGNED_INT = 0x1405;
	public static inline var UNIFORM_BUFFER_OFFSET_ALIGNMENT = 0x8A34;
	public static inline var INVALID_INDEX = -1;
	public static inline var DEPTH_TEST = 0x0B71;
	public static inline var BLEND = 0x0BE2;
	public static inline var FUNC_ADD = 0x8006;
	public static inline var ZERO = 0;
	public static inline var ONE = 1;
	public static inline var SRC_ALPHA = 0x0302;
	public static inline var ONE_MINUS_SRC_ALPHA = 0x0303;
	public static inline var NEVER = 0x0200; // LESS, EQUAL, LEQUAL, GREATER, NOTEQUAL, GEQUAL, ALWAYS: + 1 to + 7
	public static inline var TEXTURE_2D = 0x0DE1;
	public static inline var TEXTURE0 = 0x84C0;
	public static inline var RGBA8 = 0x8058;
	public static inline var UNPACK_ALIGNMENT = 0x0CF5;
	public static inline var TEXTURE_MAG_FILTER = 0x2800;
	public static inline var TEXTURE_MIN_FILTER = 0x2801;
	public static inline var TEXTURE_WRAP_S = 0x2802;
	public static inline var TEXTURE_WRAP_T = 0x2803;
	public static inline var NEAREST = 0x2600;
	public static inline var LINEAR = 0x2601;
	public static inline var REPEAT = 0x2901;
	public static inline var CLAMP_TO_EDGE = 0x812F;
	public static inline var MIRRORED_REPEAT = 0x8370;
	public static inline var NEAREST_MIPMAP_NEAREST = 0x2700; // LINEAR_MIPMAP_NEAREST, NEAREST_MIPMAP_LINEAR, LINEAR_MIPMAP_LINEAR: + 1 to + 3
	public static inline var CW = 0x0900;
	public static inline var R8 = 0x8229;
	public static inline var RG8 = 0x822B;
	public static inline var SRGB8_ALPHA8 = 0x8C43;
	public static inline var RGBA16F = 0x881A;
	public static inline var R32F = 0x822E;
	public static inline var DEPTH_COMPONENT16 = 0x81A5;
	public static inline var DEPTH_COMPONENT32F = 0x8CAC;
	public static inline var RED = 0x1903;
	public static inline var RG = 0x8227;
	public static inline var DEPTH_COMPONENT = 0x1902;
	public static inline var HALF_FLOAT = 0x140B;
	public static inline var FRAMEBUFFER = 0x8D40;
	public static inline var COLOR_ATTACHMENT0 = 0x8CE0;
	public static inline var DEPTH_ATTACHMENT = 0x8D00;
	public static inline var FRAMEBUFFER_COMPLETE = 0x8CD5;
	public static inline var READ_FRAMEBUFFER = 0x8CA8;
	public static inline var DRAW_FRAMEBUFFER = 0x8CA9;
	public static inline var RENDERBUFFER = 0x8D41;

	static function glGetString(name:Int):Ptr;
	static function glGetError():Int;
	static function glEnable(cap:Int):Void;
	static function glDisable(cap:Int):Void;
	static function glCullFace(mode:Int):Void;
	static function glFrontFace(mode:Int):Void;
	static function glViewport(x:Int, y:Int, width:Int, height:Int):Void;
	static function glClearColor(r:Float32, g:Float32, b:Float32, a:Float32):Void;
	static function glClear(mask:Int):Void;
	static function glGenBuffers(n:Int, buffers:Ptr<Int32>):Void;
	static function glDeleteBuffers(n:Int, buffers:Ptr<Int32>):Void;
	static function glDeleteTextures(n:Int, textures:Ptr<Int32>):Void;
	static function glBindBuffer(target:Int, buffer:Int):Void;
	static function glBufferData(target:Int, size:Int64, data:Ptr, usage:Int):Void;
	static function glBufferSubData(target:Int, offset:Int64, size:Int64, data:Ptr):Void;
	static function glCreateShader(type:Int):Int;
	static function glShaderSource(shader:Int, count:Int, strings:Ptr<Ptr>, lengths:Ptr<Int32>):Void;
	static function glCompileShader(shader:Int):Void;
	static function glGetShaderiv(shader:Int, pname:Int, value:Ptr<Int32>):Void;
	static function glGetShaderInfoLog(shader:Int, size:Int, length:Ptr<Int32>, log:Ptr):Void;
	static function glDeleteShader(shader:Int):Void;
	static function glCreateProgram():Int;
	static function glAttachShader(program:Int, shader:Int):Void;
	static function glLinkProgram(program:Int):Void;
	static function glGetProgramiv(program:Int, pname:Int, value:Ptr<Int32>):Void;
	static function glGetProgramInfoLog(program:Int, size:Int, length:Ptr<Int32>, log:Ptr):Void;
	static function glUseProgram(program:Int):Void;
	static function glDeleteProgram(program:Int):Void;
	static function glGenVertexArrays(n:Int, arrays:Ptr<Int32>):Void;
	static function glBindVertexArray(array:Int):Void;
	static function glEnableVertexAttribArray(index:Int):Void;
	static function glDisableVertexAttribArray(index:Int):Void;
	static function glVertexAttribPointer(index:Int, size:Int, type:Int, normalized:Bool, stride:Int, offset:Ptr):Void;
	static function glVertexAttribDivisor(index:Int, divisor:Int):Void;
	static function glDrawArrays(mode:Int, first:Int, count:Int):Void;
	static function glDrawArraysInstanced(mode:Int, first:Int, count:Int, instances:Int):Void;
	static function glDrawElements(mode:Int, count:Int, type:Int, offset:Ptr):Void;
	static function glDrawElementsInstanced(mode:Int, count:Int, type:Int, offset:Ptr, instances:Int):Void;
	static function glGetIntegerv(pname:Int, value:Ptr<Int32>):Void;
	static function glBindBufferRange(target:Int, index:Int, buffer:Int, offset:Int64, size:Int64):Void;
	static function glGetUniformBlockIndex(program:Int, name:Ptr):Int;
	static function glUniformBlockBinding(program:Int, index:Int, binding:Int):Void;
	static function glGetUniformLocation(program:Int, name:Ptr):Int;
	static function glUniform1i(location:Int, x:Int):Void;
	static function glUniform1f(location:Int, x:Float32):Void;
	static function glUniform2f(location:Int, x:Float32, y:Float32):Void;
	static function glBlendFuncSeparate(srcRGB:Int, dstRGB:Int, srcAlpha:Int, dstAlpha:Int):Void;
	static function glBlendEquation(mode:Int):Void;
	static function glDepthFunc(func:Int):Void;
	static function glDepthMask(flag:Bool):Void;
	static function glClearDepthf(depth:Float32):Void;
	static function glGenTextures(n:Int, textures:Ptr<Int32>):Void;
	static function glBindTexture(target:Int, texture:Int):Void;
	static function glActiveTexture(unit:Int):Void;
	static function glTexStorage2D(target:Int, levels:Int, internalFormat:Int, width:Int, height:Int):Void;
	static function glGenerateMipmap(target:Int):Void;
	static function glGenFramebuffers(n:Int, framebuffers:Ptr<Int32>):Void;
	static function glDeleteFramebuffers(n:Int, framebuffers:Ptr<Int32>):Void;
	static function glBindFramebuffer(target:Int, framebuffer:Int):Void;
	static function glFramebufferTexture2D(target:Int, attachment:Int, textarget:Int, texture:Int, level:Int):Void;
	static function glCheckFramebufferStatus(target:Int):Int;
	// (multisampled render targets: renderbuffers, resolved by a blit)
	static function glGenRenderbuffers(n:Int, renderbuffers:Ptr<Int32>):Void;
	static function glDeleteRenderbuffers(n:Int, renderbuffers:Ptr<Int32>):Void;
	static function glBindRenderbuffer(target:Int, renderbuffer:Int):Void;
	static function glRenderbufferStorageMultisample(target:Int, samples:Int, internalFormat:Int, width:Int, height:Int):Void;
	static function glFramebufferRenderbuffer(target:Int, attachment:Int, renderbufferTarget:Int, renderbuffer:Int):Void;
	static function glBlitFramebuffer(x0:Int, y0:Int, x1:Int, y1:Int, dx0:Int, dy0:Int, dx1:Int, dy1:Int, mask:Int, filter:Int):Void;
	static function glTexSubImage2D(target:Int, level:Int, x:Int, y:Int, width:Int, height:Int, format:Int, type:Int, pixels:Ptr):Void;
	static function glGenSamplers(n:Int, samplers:Ptr<Int32>):Void;
	#if hxmc.dev
	// (hxmc dev: a build swapped out deletes what it made, the context kept)
	static function glDeleteSamplers(n:Int, samplers:Ptr<Int32>):Void;
	static function glDeleteVertexArrays(n:Int, arrays:Ptr<Int32>):Void;
	#end
	static function glSamplerParameteri(sampler:Int, pname:Int, param:Int):Void;
	static function glBindSampler(unit:Int, sampler:Int):Void;
	static function glPixelStorei(pname:Int, param:Int):Void;
	@:wait static function glReadPixels(x:Int, y:Int, width:Int, height:Int, format:Int, type:Int, pixels:Ptr):Void;
	@:wait static function glFinish():Void;
}
