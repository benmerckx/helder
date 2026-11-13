package helder.text.linux;

import hxmc.unsafe.*;

// fontconfig (Linux), loaded at run time (helder.os.Dl: no fontconfig, no
// answers, null): the system's font for a character the app's fonts lack,
// as the desktop's own text finds it (a pattern of that character's
// charset, the configuration's and the defaults' substitutions,
// FcFontMatch; the match kept only when it has the character), and a
// family's face closest to a weight and style.
@:hxmc.unsafe(gc)
class Fontconfig {
	static var ready = 0; // (0: not tried, 1: there, -1: none)

	public static function available():Bool {
		if (ready == 0) ready = Fc.load("libfontconfig.so.1") == null && Fc.FcInit() != 0 ? 1 : -1;
		return ready > 0;
	}

	// the file and face index of a font with the character (null: none)
	public static function fileFor(cp:Int, ?lang:String):Null<{path:String, index:Int}> {
		if (!available()) return null;
		var p = Fc.FcPatternCreate(), cs = Fc.FcCharSetCreate();
		Fc.FcCharSetAddChar(cs, cp);
		Fc.FcPatternAddCharSet(p, Mem.cstr("charset"), cs);
		if (lang != null) Arena.scoped(a -> Fc.FcPatternAddString(p, Mem.cstr("lang"), a.cstring(lang)));
		var out = match(p, cp, null);
		Fc.FcCharSetDestroy(cs);
		return out;
	}

	// a family's face (weight: OpenType's 100 to 900); null: the system has none of that family
	public static function family(name:String, weight:Int, italic:Bool):Null<{path:String, index:Int}> {
		if (!available()) return null;
		var p = Fc.FcPatternCreate();
		Arena.scoped(a -> Fc.FcPatternAddString(p, Mem.cstr("family"), a.cstring(name)));
		Fc.FcPatternAddInteger(p, Mem.cstr("weight"), Fc.FcWeightFromOpenType(weight));
		Fc.FcPatternAddInteger(p, Mem.cstr("slant"), italic ? 100 : 0); // (FC_SLANT_ITALIC, FC_SLANT_ROMAN)
		return match(p, -1, name);
	}

	// (the pattern matched, then destroyed; kept when the match has cp, or is of family)
	static function match(p:Ptr, cp:Int, family:Null<String>):Null<{path:String, index:Int}> {
		Fc.FcConfigSubstitute(Ptr.nil(), p, 0); // (FcMatchPattern)
		Fc.FcDefaultSubstitute(p);
		var out:Null<{path:String, index:Int}> = null;
		Arena.scoped(a -> {
			var result:Ptr<Int32> = a.alloc(4);
			var m = Fc.FcFontMatch(Ptr.nil(), p, cast result);
			if (m.isNull()) return;
			var file:Ptr<Ptr> = a.alloc(8), index:Ptr<Int32> = a.alloc(4), has:Ptr<Ptr> = a.alloc(8), fam:Ptr<Ptr> = a.alloc(8);
			index.value = 0;
			// (FcResultMatch 0)
			var ok = Fc.FcPatternGetString(m, Mem.cstr("file"), 0, cast file) == 0;
			if (ok && cp >= 0) ok = Fc.FcPatternGetCharSet(m, Mem.cstr("charset"), 0, cast has) == 0 && Fc.FcCharSetHasChar(has.value, cp) != 0;
			if (ok && family != null) {
				ok = false;
				var k = 0;
				while (Fc.FcPatternGetString(m, Mem.cstr("family"), k++, cast fam) == 0)
					if ((cast fam.value : CString).toString().toLowerCase() == family.toLowerCase()) ok = true;
			}
			if (ok) {
				Fc.FcPatternGetInteger(m, Mem.cstr("index"), 0, cast index);
				out = {path: (cast file.value : CString).toString(), index: index.value};
			}
			Fc.FcPatternDestroy(m);
		});
		Fc.FcPatternDestroy(p);
		return out;
	}
}

@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class Fc {
	static function FcInit():Int;
	static function FcPatternCreate():Ptr;
	static function FcPatternDestroy(p:Ptr):Void;
	static function FcCharSetCreate():Ptr;
	static function FcCharSetDestroy(c:Ptr):Void;
	static function FcCharSetAddChar(c:Ptr, cp:Int):Int;
	static function FcCharSetHasChar(c:Ptr, cp:Int):Int;
	static function FcPatternAddCharSet(p:Ptr, object:Ptr, c:Ptr):Int;
	static function FcPatternAddString(p:Ptr, object:Ptr, s:Ptr):Int;
	static function FcPatternAddInteger(p:Ptr, object:Ptr, i:Int):Int;
	static function FcWeightFromOpenType(w:Int):Int;
	static function FcConfigSubstitute(config:Ptr, p:Ptr, kind:Int):Int;
	static function FcDefaultSubstitute(p:Ptr):Void;
	static function FcFontMatch(config:Ptr, p:Ptr, result:Ptr):Ptr;
	static function FcPatternGetString(p:Ptr, object:Ptr, n:Int, s:Ptr):Int;
	static function FcPatternGetInteger(p:Ptr, object:Ptr, n:Int, i:Ptr):Int;
	static function FcPatternGetCharSet(p:Ptr, object:Ptr, n:Int, c:Ptr):Int;
}
