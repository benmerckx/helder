package helder.asset;

using StringTools;

// An asset's path as code names it (Asset.image("ui/icons/sword.png")): its
// key in every bundle (the executable's data, the APK's assets/, the app's
// assets/, the files beside a page), so the same on every platform:
// relative, '/' between its parts, none of them empty, "." or "..", no
// backslash, colon or control character (Windows' and URLs' meanings), and
// the case of the file as it is on disk (Android's and the web's file
// names are case-sensitive, macOS's and Windows' disks usually not). Pure:
// the macro checks a path with it when compiling, its tests
// (AssetPath.test.hx) without a compiler.
class AssetPath {
	// why path is not an asset's path, or null when it is one
	public static function error(path:String):Null<String> {
		if (path == "") return "an empty path";
		if (path.startsWith("/")) return 'an absolute path (assets are named relative to the project or a class path)';
		if (path.indexOf("\\") >= 0) return "a backslash ('/' separates the parts on every platform)";
		if (path.indexOf(":") >= 0) return "a colon (a drive or a URL's scheme: assets are named relative to the project or a class path)";
		for (i in 0...path.length) {
			var c = path.charCodeAt(i);
			if (c < 0x20 || c == 0x7f) return "a control character";
		}
		for (p in path.split("/"))
			switch p {
				case "": return "an empty part (a '/' doubled or at the end)";
				case "." | "..": return 'a part "$p" (the path as it is, from its root)';
				case _:
			}
		return null;
	}

	// the parts of path that differ in case from the names in their
	// directories (list: a directory's names), or null when every part is
	// there as written; [part, name on disk] for the first that differs, or
	// [part, null] for one not there at all
	public static function caseOf(path:String, list:String->Array<String>):Null<{part:String, actual:Null<String>}> {
		var dir = "";
		for (p in path.split("/")) {
			var names = list(dir);
			if (!names.contains(p)) {
				var lower = p.toLowerCase();
				for (n in names)
					if (n.toLowerCase() == lower) return {part: p, actual: n};
				return {part: p, actual: null};
			}
			dir = dir == "" ? p : '$dir/$p';
		}
		return null;
	}

	// the path in a bundle: the APK's assets/<key> (AAssetManager's name: the
	// key), the app's and a page's assets/<key>
	public static inline function bundled(key:String):String
		return "assets/" + key;

	// a key as a URL's path (each part percent-encoded, the '/' kept)
	public static function url(key:String):String
		return [for (p in key.split("/")) p.urlEncode()].join("/");
}
