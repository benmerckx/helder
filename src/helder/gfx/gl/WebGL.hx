package helder.gfx.gl;

// The GL back end's contexts in the browser (WebAssembly): WebGL2 through
// imports of the module "hxmc_gl", next to the GL functions themselves
// (Loader), which src/helder/gfx/imports.mjs provides. A context is a handle
// into the loader's table of JavaScript objects (0: none).
@:hxmc.c @:hxmc.fast @:hxmc.lib("hxmc_gl") extern class WebGL {
	// a WebGL2 context on a canvas (its handle: helder.os.Surface's) or, canvas
	// 0, on an offscreen one of width x height; 0: no WebGL2 here; antialias
	// 1: a canvas's frames multisampled (the page's run option antialias, when set, decides)
	static function context(canvas:Int, width:Int, height:Int, antialias:Int):Int;
	// the context the GL functions draw with (eglMakeCurrent)
	static function make_current(context:Int):Void;
	// the end of a frame (the browser presents a canvas when the task ends)
	static function swap(context:Int):Void;
	static function release(context:Int):Void;
	// the GL texture (RGBA8 or RGBA8Srgb, the image's size) filled from a
	// browser image (helder_image's), at once when it is decoded, else once
	// it is (the texture unit 0's binding kept); levels > 1: its mips
	// generated then; release 1: the image freed after
	static function texture_image(texture:Int, image:Int, levels:Int, release:Int):Void;
}
