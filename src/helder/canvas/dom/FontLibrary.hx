package helder.canvas.dom;

import helder.text.FontFile;

// The fonts a context's `font` names, as skia-canvas's FontLibrary: files
// registered under a family (their own name, or an alias), chosen by the
// weight and style the font asks for; families it does not have are the
// system's (helder.text's SystemFonts).
class FontLibrary {
	static final registered = new Map<String, Array<FontFile>>();
	static final order:Array<String> = [];

	// every face of the files at paths, under family (null: each file's own family name); their family names
	public static function use(family:Null<String>, paths:Array<String>):Array<String> {
		var names = [];
		for (p in paths)
			for (f in helder.text.SystemFonts.get().add(sys.io.File.getBytes(p))) {
				var name = family ?? f.family;
				addFace(name, f);
				if (names.indexOf(name) < 0) names.push(name);
			}
		return names;
	}

	@:noCompletion public static function addFace(family:String, f:FontFile) {
		var key = family.toLowerCase();
		if (!registered.exists(key)) {
			registered.set(key, []);
			order.push(family);
		}
		registered.get(key).push(f);
	}

	public static function has(family:String):Bool
		return registered.exists(family.toLowerCase());

	public static function families():Array<String>
		return order.copy();

	public static function reset() {
		registered.clear();
		order.resize(0);
	}

	// the face of family closest to weight and italic (null: none registered)
	@:noCompletion public static function face(family:String, weight:Int, italic:Bool):Null<FontFile> {
		var list = registered.get(family.toLowerCase());
		if (list == null || list.length == 0) return null;
		var best = list[0], score = 1e9;
		for (f in list) {
			var s = Math.abs(f.weight - weight) + (f.italic != italic ? 1000 : 0);
			if (s < score) {
				score = s;
				best = f;
			}
		}
		return best;
	}

	// every registered face: the fallbacks of text in a family that lacks a character
	@:noCompletion public static function all():Array<FontFile> {
		var out = [];
		for (k in order)
			for (f in registered.get(k.toLowerCase()))
				out.push(f);
		return out;
	}
}
