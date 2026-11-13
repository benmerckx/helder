package helder.os;

import hxmc.Platform;

import hxmc.unsafe.*;

// A small key-value store kept between runs: an app's settings, a game's
// save. Strings by key, read into memory when opened, written through at
// each change (set, remove, clear), where the platform keeps an app's data:
//
//   Linux     $XDG_DATA_HOME/<name>/store.json (~/.local/share/<name>/)
//   macOS     ~/Library/Application Support/<name>/store.json
//   Windows   %APPDATA%\<name>\store.json
//   Android   the app's files directory (ANativeActivity's internalDataPath)/<name>.json
//   iOS       the app's Library/Application Support/<name>.json ($HOME is its container)
//   the web   localStorage, the item "helder.store/<name>" (an origin's: a
//             page of several programs names each its own)
//
//   var save = Store.open("golf");
//   var best = save.get("best") ?? "";
//   save.set("best", "3,2,4");
//
// The file is JSON (an object of strings), written to a temporary file then
// renamed over the old one, so a crash mid-write leaves the last one whole.
// A store that cannot be read (none yet, damaged) opens empty; one that
// cannot be written (a read-only disk, a private window) keeps its values
// for the run (written false). dir puts the file elsewhere (tests; wasm32
// without localStorage, as under node's WASI: "." by default). In a
// headless run (-D helder.headless) a store without dir starts empty and
// stays in memory: what an earlier run, or the user's own app, kept does
// not change what the run shows, and the run keeps nothing.
class Store {
	public final name:String;
	// the file (the web: "")
	public final path:String;
	// whether the last change reached the disk or localStorage
	public var written(default, null) = true;

	final values = new Map<String, String>();
	final web:Bool;
	// (a scope's: in memory, never read or written)
	var memory = false;

	// the stores open() gives while set (null: the platform's): a screen's of
	// a story host (helder.ui.ScreenContext, which sets it while current),
	// each name's store in memory, kept for the run
	public static var scope:Null<Map<String, Store>> = null;

	function new(name:String, path:String, web:Bool, memory = false) {
		this.name = name;
		this.path = path;
		this.web = web;
		this.memory = memory;
		if (memory) return;
		var text:Null<String> = null;
		#if helder.headless
		if (path == "") return;
		#end
		#if (hxmc.target == "wasm32-wasi")
		if (web) {
			var h = Arena.scopedValue(a -> helder.os.web.Dom.store_get(a.cstring(item())));
			if (h != 0) text = @:privateAccess helder.os.web.CanvasWindow.take(h);
		} else
		#end
			text = try sys.io.File.getContent(path) catch (_:Dynamic) null;
		if (text != null) try {
			var o:haxe.DynamicAccess<Dynamic> = haxe.Json.parse(text);
			for (k in o.keys())
				if (Std.isOfType(o.get(k), String)) values.set(k, o.get(k));
		} catch (_:Dynamic) {}
	}

	// the store of that name (letters, digits, '.', '-' and '_'), in the platform's place or in dir
	public static function open(name:String, ?dir:String):Store {
		if (!~/^[A-Za-z0-9._-]+$/.match(name) || name.charAt(0) == ".") throw 'helder.os.Store: a name of letters, digits, ".", "-" and "_": $name';
		if (scope != null && dir == null) {
			var s = scope.get(name);
			if (s == null) {
				s = new Store(name, "", false, true);
				scope.set(name, s);
			}
			return s;
		}
		#if (hxmc.target == "wasm32-wasi")
		if (dir == null && helder.os.web.Dom.store_available() != 0) return new Store(name, "", true);
		#end
		#if helder.headless
		if (dir == null) return new Store(name, "", false);
		#end
		return new Store(name, dir != null ? dir + "/" + name + ".json" : place(name), false);
	}

	// (the platform's file for the app's data, its directory made when missing)
	static function place(name:String):String {
		var d:String, file = name + ".json";
		if (Platform.os() == 3) d = "." else if (Platform.apple() >= 1) d = Sys.getEnv("HOME") + "/Library/Application Support" else if (Platform.target() >= 9)
			d = #if (hxmc.target == "wasm32-wasi") "." #else androidFiles() #end else {
			file = "store.json";
			d = if (Platform.os() == 1) Sys.getEnv("HOME") + "/Library/Application Support/" + name else if (Platform.os() == 2)
				(Sys.getEnv("APPDATA") ?? Sys.getEnv("USERPROFILE") + "\\AppData\\Roaming") + "\\" + name else
				(Sys.getEnv("XDG_DATA_HOME") ?? Sys.getEnv("HOME") + "/.local/share") + "/" + name;
		}
		try if (!sys.FileSystem.exists(d)) sys.FileSystem.createDirectory(d) catch (_:Dynamic) {}
		return d + "/" + file;
	}

	#if (hxmc.target != "wasm32-wasi")
	// (Android: ANativeActivity.internalDataPath, the app's files directory)
	static function androidFiles():String {
		var a = helder.os.android.Activity.activity;
		if (a.isNull()) return ".";
		var p:CString = cast Mem.getPtr(a, 32);
		return p.isNull() ? "." : p.toString();
	}
	#end

	inline function item():String
		return "helder.store/" + name;

	public function get(key:String):Null<String>
		return values.get(key);

	public function exists(key:String):Bool
		return values.exists(key);

	public function keys():Array<String> {
		var out = [for (k in values.keys()) k];
		out.sort(Reflect.compare);
		return out;
	}

	public function set(key:String, value:String) {
		if (values.get(key) == value) return;
		values.set(key, value);
		write();
	}

	public function remove(key:String) {
		if (!values.remove(key)) return;
		write();
	}

	public function clear() {
		values.clear();
		write();
	}

	// (the whole store, its keys in order)
	function text():String {
		var o:haxe.DynamicAccess<String> = {};
		for (k in keys())
			o.set(k, values.get(k));
		return haxe.Json.stringify(o);
	}

	function write() {
		if (memory) return;
		#if helder.headless
		if (path == "" && !web) return;
		#end
		#if (hxmc.target == "wasm32-wasi")
		if (web) {
			var t = text();
			Arena.scoped(a -> helder.os.web.Dom.store_set(a.cstring(item()), a.cstring(t)));
			written = true;
			return;
		}
		#end
		written = try {
			var tmp = path + ".tmp";
			sys.io.File.saveContent(tmp, text());
			// (Windows' rename does not replace)
			if (Platform.os() == 2 && sys.FileSystem.exists(path)) sys.FileSystem.deleteFile(path);
			sys.FileSystem.rename(tmp, path);
			true;
		} catch (_:Dynamic) false;
	}
}
