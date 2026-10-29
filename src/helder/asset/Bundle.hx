package helder.asset;

import haxe.io.Bytes;

using StringTools;

// The files a build takes with it: those its code names (Asset's macros,
// Model.of) and still uses after dead code elimination, read from the
// build's output (helder's CLI, after each build: BuildCommand's).
//
// Each call Asset's macros make names its key in a marker, a string literal
// of its own: MARK, "key:" (or "now:" for a read before main, Model.of's),
// the key, \x01 (Assets.key takes the key from it). hxmc emits the literals
// of the code it keeps only, so the keys whose markers are in the output
// (the executable, the library, the module; as UTF-8 or as UTF-16) are
// those the program uses. On desktop the files are resources of the
// executable (AssetMacro: Context.addResource, from the macro, so that a
// cached module keeps them), each after a header naming it (MARK, "res:",
// the key, \x01): the output also says which it has. Those are the ones a
// last build used (-D helder.asset.keep=<file>: the macro leaves the others
// out, and its module is typed again when the file changes), else every
// one named; when they differ from the used ones the CLI writes the file
// and builds again. iOS's bundle, Android's APK and the web's files are
// made by the CLI from the used ones (iOS's before linking: the last
// build's, then the same check).
//
// Pure (the CLI's, natively; its tests): scan, and locate, a path's file
// under roots as the macro finds it.
// Hooks for later: a file's settings beside it (sword.png.meta) and a
// format per target (compressed textures) would be read and applied where
// the CLI copies or the macro embeds a file.
class Bundle {
	// the markers' start (then "key:", "now:" or "res:", the key, \x01)
	public static inline var MARK = "helder.asset.";
	// a resource's name (desktop): PREFIX and the key
	public static inline var PREFIX = "helder.asset/";

	// the keys whose markers b has: used (true: read before main) and built
	// in (desktop's resources' headers)
	public static function scan(b:Bytes):{used:Map<String, Bool>, built:Array<String>} {
		var used = new Map<String, Bool>(), built = [];
		function found(kind:String, key:String)
			if (AssetPath.error(key) == null)
				switch kind {
					case "key:" | "now:": used.set(key, kind == "now:" || used.get(key) == true);
					case "res:": if (!built.contains(key)) built.push(key);
					case _:
				}
		var n = b.length, m = MARK.length;
		// (UTF-8, then UTF-16 little-endian)
		for (wide in [false, true]) {
			var step = wide ? 2 : 1, first = MARK.charCodeAt(0);
			var i = 0;
			while (i + m * step + 4 * step < n) {
				if (b.get(i) != first || wide && b.get(i + 1) != 0) {
					i++;
					continue;
				}
				var k = 1;
				while (k < m && b.get(i + k * step) == MARK.charCodeAt(k) && (!wide || b.get(i + k * step + 1) == 0))
					k++;
				if (k < m) {
					i++;
					continue;
				}
				// (the rest: up to \x01, a key's length at most)
				var p = i + m * step, s = new StringBuf(), end = false;
				while (p + step <= n && p - i < 8192) {
					var c = wide ? b.get(p) | b.get(p + 1) << 8 : b.get(p);
					p += step;
					if (c == 1) {
						end = true;
						break;
					}
					if (c < 0x20) break;
					s.addChar(c);
				}
				var t = s.toString();
				if (end && t.length > 4) found(t.substr(0, 4), wide ? t.substr(4) : utf8(t.substr(4)));
				i = p;
			}
		}
		built.sort(Reflect.compare);
		return {used: used, built: built};
	}

	// (bytes read one per character: their UTF-8 decoded)
	static function utf8(s:String):String {
		var b = Bytes.alloc(s.length);
		for (i in 0...s.length)
			b.set(i, s.charCodeAt(i));
		return b.toString();
	}

	// path's file under the first root that has it in that case (list: a
	// directory's names, null when there is none), or null; mismatch told of
	// a part there in another case
	public static function locate(path:String, roots:Array<String>, list:String->Null<Array<String>>,
			?mismatch:{part:String, actual:String}->Void):Null<String> {
		for (r in roots) {
			var c = AssetPath.caseOf(path, d -> list(d == "" ? r : '$r/$d') ?? []);
			if (c == null) return '$r/$path';
			if (c.actual != null && mismatch != null) mismatch({part: c.part, actual: c.actual});
		}
		return null;
	}
}
