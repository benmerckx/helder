package studio;

// The project's files, wherever they are: the disk natively (sys), and in
// the browser the page's copy of the project, which lives in the origin's
// private file system (OPFS) and is written through to it (and to the
// folder it was opened from, when the page may write there): studio.web's
// StudioWeb, apps/studio/web/studio.mjs. Paths are absolute ('/'-separated).
class Files {
	public static function read(path:String):String {
		#if (hxmc.target == "wasm32-wasi")
		var h = hxmc.unsafe.Arena.scopedValue(a -> studio.web.StudioWeb.fs_read(a.cstring(path)));
		if (h == 0) throw '$path: no such file';
		return studio.web.StudioWeb.WebText.take(h);
		#else
		return sys.io.File.getContent(path);
		#end
	}

	public static function save(path:String, text:String) {
		#if (hxmc.target == "wasm32-wasi")
		hxmc.unsafe.Arena.scoped(a -> studio.web.StudioWeb.fs_write(a.cstring(path), a.cstring(text)));
		#else
		sys.io.File.saveContent(path, text);
		#end
	}

	public static function exists(path:String):Bool {
		#if (hxmc.target == "wasm32-wasi")
		return hxmc.unsafe.Arena.scopedValue(a -> studio.web.StudioWeb.fs_exists(a.cstring(path))) != 0;
		#else
		return sys.FileSystem.exists(path);
		#end
	}

	public static function isDirectory(path:String):Bool {
		#if (hxmc.target == "wasm32-wasi")
		return hxmc.unsafe.Arena.scopedValue(a -> studio.web.StudioWeb.fs_exists(a.cstring(path))) == 2;
		#else
		return sys.FileSystem.isDirectory(path);
		#end
	}

	// a directory's entries' names (none: [])
	public static function list(dir:String):Array<String> {
		#if (hxmc.target == "wasm32-wasi")
		var h = hxmc.unsafe.Arena.scopedValue(a -> studio.web.StudioWeb.fs_list(a.cstring(dir)));
		return h == 0 ? [] : haxe.Json.parse(studio.web.StudioWeb.WebText.take(h));
		#else
		return try sys.FileSystem.readDirectory(dir) catch (_:Dynamic) [];
		#end
	}

	// a directory's full path, '/'-separated
	public static function full(path:String):String {
		#if (hxmc.target == "wasm32-wasi")
		return haxe.io.Path.normalize(path);
		#else
		return sys.FileSystem.fullPath(path).split("\\").join("/");
		#end
	}
}
