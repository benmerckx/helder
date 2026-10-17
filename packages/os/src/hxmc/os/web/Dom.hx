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
	// the next pending event into ev (seven Int32: canvas, EventKind, key (a
	// TextInput's code point), x, y, button, mods); 0: none
	static function next_event(ev:Ptr<Int32>):Int;
	// the clipboard: write; read (its text comes back as an event of kind 100,
	// key: a string handle, 0 for none)
	static function clipboard_write(text:CString):Void;
	static function clipboard_read():Void;
	// a string handle's UTF-8 length; its bytes into p (the handle freed)
	static function text_length(h:Int):Int;
	static function text_take(h:Int, p:Ptr):Void;
	// the canvas's CSS cursor, by Cursor
	static function set_cursor(canvas:Int, cursor:Int):Void;
	// requestAnimationFrame calls frame (a @:hxmc.callback ():Int) until it returns 0
	static function start(frame:Ptr):Void;
}
