package helder.async;

#if (hxmc.target == "wasm32-wasi")
import hxmc.unsafe.*;

// The page's side of the loop (WebAssembly): imports of the module
// "helder_async", which src/helder/async/imports.mjs provides (browser.mjs's
// option imports).
@:hxmc.c @:hxmc.lib("helder_async") extern class Web {
	// the loop's turns from now on: turn (a @:hxmc.callback ():Float, the
	// seconds until it wants the next, -1 for none) run by the page's event loop
	static function start(turn:Ptr):Void;
	// a turn wanted in that many seconds at the latest
	static function wake(seconds:Float):Void;
	// a fetch of url (relative to the page) started: its handle; its state (0
	// loading, 1 done, -1 failed; a turn comes when it changes), its body's
	// length, the body into p (the handle freed); fetch_free aborts it
	static function fetch_start(url:CString):Int;
	static function fetch_state(h:Int):Int;
	static function fetch_length(h:Int):Int;
	static function fetch_take(h:Int, p:Ptr):Void;
	static function fetch_free(h:Int):Void;
}
#end
