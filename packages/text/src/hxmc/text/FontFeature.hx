package hxmc.text;

// An OpenType feature asked of a text (FontSet.features; CSS's
// font-feature-settings): its tag and value (0: off; 1: on; n: an alternate
// substitution's nth glyph). Parsed as CSS writes them: "'tnum'",
// "\"liga\" 0, 'ss01' on, 'salt' 2"; "normal": none.
@:structInit class FontFeature {
	public var tag:String;
	public var value:Int = 1;

	public static function parse(s:String):Array<FontFeature> {
		var out:Array<FontFeature> = [];
		if (StringTools.trim(s) == "normal") return out;
		for (part in s.split(",")) {
			var p = StringTools.trim(part);
			var q = p.length > 0 ? p.charAt(0) : "";
			if ((q != "'" && q != "\"") || p.length < 6 || p.charAt(5) != q) throw "FontFeature.parse: " + s;
			var tag = p.substr(1, 4), rest = StringTools.trim(p.substr(6)), value = 1;
			for (i in 0...4) {
				var c = StringTools.fastCodeAt(tag, i);
				if (c < 0x20 || c > 0x7E) throw "FontFeature.parse: " + s;
			}
			if (rest == "on" || rest == "") value = 1 else if (rest == "off") value = 0 else {
				var n = Std.parseInt(rest);
				if (n == null || n < 0 || Std.string(n) != rest) throw "FontFeature.parse: " + s;
				value = n;
			}
			// (a tag again: the last one's value)
			for (f in out)
				if (f.tag == tag) out.remove(f);
			out.push({tag: tag, value: value});
		}
		return out;
	}

	// (the features as one string: what caches are kept by)
	public static function key(fs:Array<FontFeature>):String
		return [for (f in fs) f.tag + "=" + f.value].join(",");
}
