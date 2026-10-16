package hxmc.os.web;

import hxmc.unsafe.*;

// The browser's side of hxmc.os (WebAssembly): imports of the module
// "hxmc_os", which packages/os/imports.mjs provides (loaded by
// packages/os/browser.mjs). Canvases are handles into the loader's table of
// JavaScript objects (0: none); sizes are in pixels of the drawing buffer.
@:hxmc.c @:hxmc.lib("hxmc_os") extern class Dom {
	// a canvas for a new window (the loader's `canvas` option, else a new
	// element at the end of the page), its buffer width x height CSS pixels
	static function window_open(title:CString, width:Int, height:Int):Int;
	static function window_close(canvas:Int):Void;
	// the canvas element of that id (0: none)
	static function canvas(id:CString):Int;
	static function width(canvas:Int):Int;
	static function height(canvas:Int):Int;
	// device pixels per CSS pixel
	static function scale():Float;
	// the next pending event into ev (six Int32: canvas, EventKind, key, x, y,
	// button); 0: none
	static function next_event(ev:Ptr<Int32>):Int;
	// requestAnimationFrame calls frame (a @:hxmc.callback ():Int) until it returns 0
	static function start(frame:Ptr):Void;
}
