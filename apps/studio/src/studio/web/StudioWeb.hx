package studio.web;

#if (hxmc.target == "wasm32-wasi")
import hxmc.unsafe.*;

// The studio's page in the browser (apps/studio/web/studio.mjs: the module
// "studio_web"): the project's files (the page's copy, kept in OPFS),
// projects opened, and the preview host in its worker (helder.story.web's
// worker.mjs) with its protocol's lines and its frames. Strings come back
// as handles (take), events through next.
@:hxmc.c @:hxmc.lib("studio_web") extern class StudioWeb {
	// a file's text (a string handle; 0: none), written (and saved to OPFS)
	static function fs_read(path:CString):Int;
	static function fs_write(path:CString, text:CString):Void;
	// 0 none, 1 a file, 2 a directory
	static function fs_exists(path:CString):Int;
	// a directory's names, JSON (a string handle; 0: none)
	static function fs_list(dir:CString):Int;
	// the project the page opened (JSON, a string handle; 0: none): {dir,
	// name, preview: whether it has a preview module, links: {built path:
	// the project's path}, tables: [{file, content, entries}] (the preview's
	// live literals: helder.compiler.service's tables), compiler: whether a
	// compiler is there}
	static function project():Int;
	// the welcome's lists, JSON (a string handle): the examples bundled
	// with the page, the projects in OPFS ([{name, label, screens}])
	static function examples():Int;
	static function projects():Int;
	// opening: a folder picked (the File System Access API), an example, a
	// project of OPFS; the page loads it and starts again with it
	static function open_folder():Void;
	static function open_example(name:CString):Void;
	static function open_project(name:CString):Void;
	// the preview host started (its worker; 1: there is a module to run)
	static function preview_start(gfx:Int):Int;
	// a protocol line to it
	static function preview_send(line:CString):Void;
	// the next event into ev (Int32s): 1 a line (ev[0]: its string
	// handle), 2 a frame (screen, image handle, width, height, version),
	// 3 a log line (a string handle), 4 the program ended (its code), 5
	// started (ms to start); 0: none
	static function preview_next(ev:Ptr<Int32>):Int;
	// a frame's image (its ImageBitmap) closed, its handle freed
	static function frame_release(image:Int):Void;
	// the compiler (helder.compiler.service in its worker, when there):
	// a request's JSON (its id told back as an event of kind 6, its
	// result's string handle in ev[1]); 0: no compiler
	static function compile(request:CString):Int;
	// a measure for the page (its checks: window.studioWeb.events)
	static function event(json:CString):Void;
	static function text_length(h:Int):Int;
	static function text_take(h:Int, p:Ptr):Void;
}

class WebText {
	// a string handle's text (the handle freed)
	public static function take(h:Int):String {
		var n = StudioWeb.text_length(h);
		var b = haxe.io.Bytes.alloc(n);
		Arena.scoped(a -> {
			var p = a.alloc(n + 1, 1);
			StudioWeb.text_take(h, p);
			BytesPtr.copyIn(b, 0, p, n);
		});
		return b.toString();
	}
}
#end
