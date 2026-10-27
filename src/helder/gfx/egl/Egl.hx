package helder.gfx.egl;

import hxmc.unsafe.*;

// EGL (libEGL.so.1: glvnd's or the driver's; the dynamic glibc mode). Handles
// (EGLDisplay, EGLConfig, EGLSurface, EGLContext) are Ptr, EGLint and
// EGLBoolean Int, EGLAttrib Int64; attribute lists end with NONE.
@:hxmc.c @:hxmc.lib("libEGL.so.1") extern class Egl {
	static function eglGetDisplay(native:Ptr):Ptr;
	// EGL 1.5
	static function eglGetPlatformDisplay(platform:Int, native:Ptr, attribs:Ptr<Int64>):Ptr;
	static function eglInitialize(d:Ptr, major:Ptr<Int32>, minor:Ptr<Int32>):Int;
	static function eglTerminate(d:Ptr):Int;
	static function eglBindAPI(api:Int):Int;
	static function eglChooseConfig(d:Ptr, attribs:Ptr<Int32>, configs:Ptr<Ptr>, size:Int, count:Ptr<Int32>):Int;
	// win: an X11 Window (EGLNativeWindowType: an XID on X11)
	static function eglCreateWindowSurface(d:Ptr, config:Ptr, win:Ptr, attribs:Ptr<Int32>):Ptr;
	static function eglCreatePbufferSurface(d:Ptr, config:Ptr, attribs:Ptr<Int32>):Ptr;
	static function eglDestroySurface(d:Ptr, s:Ptr):Int;
	static function eglQuerySurface(d:Ptr, s:Ptr, attribute:Int, value:Ptr<Int32>):Int;
	static function eglCreateContext(d:Ptr, config:Ptr, share:Ptr, attribs:Ptr<Int32>):Ptr;
	static function eglDestroyContext(d:Ptr, c:Ptr):Int;
	static function eglMakeCurrent(d:Ptr, draw:Ptr, read:Ptr, c:Ptr):Int;
	static function eglSwapBuffers(d:Ptr, s:Ptr):Int;
	static function eglSwapInterval(d:Ptr, interval:Int):Int;
	static function eglGetProcAddress(name:Ptr):Ptr;
	static function eglGetError():Int;
}

class EGL {
	public static inline var NONE = 0x3038;
	public static inline var SUCCESS = 0x3000;
	public static inline var RED_SIZE = 0x3024;
	public static inline var GREEN_SIZE = 0x3023;
	public static inline var BLUE_SIZE = 0x3022;
	public static inline var ALPHA_SIZE = 0x3021;
	public static inline var DEPTH_SIZE = 0x3025;
	public static inline var SURFACE_TYPE = 0x3033;
	public static inline var RENDERABLE_TYPE = 0x3040;
	public static inline var PBUFFER_BIT = 0x0001;
	public static inline var WINDOW_BIT = 0x0004;
	public static inline var OPENGL_ES3_BIT = 0x0040;
	public static inline var OPENGL_ES_API = 0x30A0;
	public static inline var CONTEXT_MAJOR_VERSION = 0x3098;
	public static inline var CONTEXT_MINOR_VERSION = 0x30FB;
	public static inline var WIDTH = 0x3057;
	public static inline var HEIGHT = 0x3056;
	public static inline var PLATFORM_X11_KHR = 0x31D5;
	public static inline var PLATFORM_SURFACELESS_MESA = 0x31DD;
}
