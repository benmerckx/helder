package helder.ui.native.dom;

import hxmc.unsafe.*;

// The browser's side of helder.ui.native (WebAssembly): imports of the module
// "hxmc_ui", which src/helder/ui/imports.mjs provides. Elements are handles
// into the loader's table (0: none).
@:hxmc.c @:hxmc.lib("hxmc_ui") extern class WebNative {
	// the container of a window's controls (run's option nativeContainer, else a new div)
	static function native_open(title:CString, width:Int, height:Int):Int;
	static function native_width(container:Int):Int;
	static function native_height(container:Int):Int;
	// a control of a ControlKind (a label for 1) in the container
	static function native_create(container:Int, kind:Int):Int;
	// its properties (JSON)
	static function native_update(element:Int, json:CString):Void;
	static function native_place(element:Int, x:Float, y:Float, width:Float, height:Float):Void;
	static function native_destroy(element:Int):Void;
	// its own size into p (two Float64)
	static function native_measure(element:Int, p:Ptr<Float>):Void;
	// text's size in a CSS font within maxWidth (negative: none) into p
	static function native_measure_text(text:CString, font:CString, maxWidth:Float, p:Ptr<Float>):Void;
	// the next event into p (handle, kind, value): 0 none
	static function native_next(p:Ptr<Int32>):Int;
	static function native_string_length(h:Int):Int;
	static function native_string_take(h:Int, p:Ptr):Void;
	// requestAnimationFrame calls frame (a @:hxmc.callback ():Int) until it returns 0
	static function native_start(frame:Ptr):Void;
}
