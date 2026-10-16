package hxmc.gfx.gl;

import hxmc.unsafe.*;

// OpenGL ES 3.0 (the subset GL 3.3 core shares): the entry points the GL
// back end calls, through pointers from GetProcAddress (Loader: GL.load).
// GLenum, GLuint, GLint, GLsizei are Int, GLsizeiptr and GLintptr Int64,
// GLboolean Bool.
@:build(hxmc.gfx.gl.Loader.build())
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
	static function glDrawArrays(mode:Int, first:Int, count:Int):Void;
	static function glDrawArraysInstanced(mode:Int, first:Int, count:Int, instances:Int):Void;
	static function glPixelStorei(pname:Int, param:Int):Void;
	@:wait static function glReadPixels(x:Int, y:Int, width:Int, height:Int, format:Int, type:Int, pixels:Ptr):Void;
	@:wait static function glFinish():Void;
}
