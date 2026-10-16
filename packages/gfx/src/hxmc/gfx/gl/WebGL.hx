package hxmc.gfx.gl;

// The GL back end's contexts in the browser (WebAssembly): WebGL2 through
// imports of the module "hxmc_gl", next to the GL functions themselves
// (Loader), which packages/gfx/imports.mjs provides. A context is a handle
// into the loader's table of JavaScript objects (0: none).
@:hxmc.c @:hxmc.fast @:hxmc.lib("hxmc_gl") extern class WebGL {
	// a WebGL2 context on a canvas (its handle: hxmc.os.Surface's) or, canvas
	// 0, on an offscreen one of width x height; 0: no WebGL2 here
	static function context(canvas:Int, width:Int, height:Int):Int;
	// the context the GL functions draw with (eglMakeCurrent)
	static function make_current(context:Int):Void;
	// the end of a frame (the browser presents a canvas when the task ends)
	static function swap(context:Int):Void;
	static function release(context:Int):Void;
}
