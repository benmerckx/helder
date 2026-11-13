package helder.os;

import haxe.io.Bytes;
import hxmc.Platform;
import hxmc.unsafe.*;

// A file handed to the user, where a browser puts what it downloads: in
// the browser the page's own download (the browser's bar, its folder);
// on macOS, Linux and Windows the user's Downloads folder, under a name
// not taken yet ("Font 2.ttf"). Where it went: the path, the name in a
// browser, null where there is none (phones) or it could not be written.
//
//   var path = Downloads.save("Pebble.ttf", bytes);
class Downloads {
	public static function save(name:String, data:Bytes, type = "application/octet-stream"):Null<String> {
		if (Platform.os() == 3) {
			download(name, data, type);
			return name;
		}
		if (Platform.apple() >= 1 || Platform.target() >= 9) return null;
		var home = Platform.os() == 2 ? Sys.getEnv("USERPROFILE") : Sys.getEnv("HOME");
		if (home == null || home == "") return null;
		var dir = home + (Platform.os() == 2 ? "\\Downloads" : "/Downloads");
		var sep = Platform.os() == 2 ? "\\" : "/";
		try {
			if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
			var dot = name.lastIndexOf("."), stem = dot > 0 ? name.substr(0, dot) : name, ext = dot > 0 ? name.substr(dot) : "";
			var path = dir + sep + name, n = 2;
			while (sys.FileSystem.exists(path))
				path = dir + sep + stem + " " + n++ + ext;
			sys.io.File.saveBytes(path, data);
			return path;
		} catch (_:Dynamic) {
			return null;
		}
	}

	static function download(name:String, data:Bytes, type:String) {
		#if (hxmc.target == "wasm32-wasi")
		Arena.scoped(a -> {
			var n = a.cstring(name), t = a.cstring(type);
			helder.os.web.Dom.download(n, hxmc.ReadOnlySpan.ofBytes(data), data.length, t);
		});
		#end
	}
}
