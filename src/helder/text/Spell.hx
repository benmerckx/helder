package helder.text;

// The platform's spellchecker, for text being edited (helder.ui's
// EditableText, spellcheck): words checked, suggestions for one, a word
// added to the user's dictionary. macOS: NSSpellChecker; Windows 8 and
// later: ISpellChecker through COM (the language's checker of
// ISpellCheckerFactory); Linux: Enchant (libenchant-2, loaded at run time:
// its providers, Hunspell's dictionaries and the user's own), else
// Hunspell itself (libhunspell, a dictionary of /usr/share/hunspell; words
// added kept for the run); both in the dynamic glibc mode (-D
// hxmc.libc=glibc, helder's builds' for Linux), none in a static one.
// None of them installed, in the browser or on a
// phone: no checker (null), spellcheck off. Off too where text is
// deterministic (helder's own text engine, Shaping.engine HELDER: tests,
// stories, screenshots), or with HELDER_NO_SPELLCHECK=1.
class Spell {
	static var tried = false;
	static var made:Null<SpellChecker> = null;
	// set: the checker every field uses (a test's; null with tried: none)
	public static var given:Null<SpellChecker> = null;

	// the system's checker for the user's language (null: none here)
	public static function checker():Null<SpellChecker> {
		if (given != null) return given;
		if (tried) return made;
		tried = true;
		if (Shaping.engine == Shaping.HELDER) return null;
		var off = Sys.getEnv("HELDER_NO_SPELLCHECK");
		if (off != null && off != "" && off != "0") return null;
		made = platform(language());
		return made;
	}

	// the platform's checker for a language, whatever the switches (null: none)
	public static function platform(lang:String):Null<SpellChecker> {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		// (constant conditions: no other system's links)
		if (hxmc.unsafe.Mem.platform() == 0) {
			if (hxmc.unsafe.Mem.os() == 0 && hxmc.unsafe.Mem.target() < 9) {
				// (Enchant and Hunspell loaded at run time: the dynamic glibc mode; a static musl build links no dlopen)
				#if (hxmc.libc == "glibc")
				return helder.text.linux.LinuxSpell.create(lang);
				#else
				return null;
				#end
			}
			else if (hxmc.unsafe.Mem.os() == 2) return helder.text.windows.WinSpell.create(lang);
			else if (hxmc.unsafe.Mem.os() == 1) return helder.text.mac.MacSpell.create(lang);
		}
		#end
		return null;
	}

	// the tags to try: the language, its base, then English
	public static function tags(lang:String):Array<String> {
		var out = [lang];
		var u = lang.indexOf("_");
		if (u > 0) out.push(lang.substr(0, u));
		for (t in ["en_US", "en"])
			if (out.indexOf(t) < 0) out.push(t);
		return out;
	}

	// the user's language as a tag: LANG's (en_US.UTF-8: en_US), else en_US
	public static function language():String {
		for (v in ["LC_ALL", "LC_MESSAGES", "LANG"]) {
			var l = Sys.getEnv(v);
			if (l == null || l == "" || l == "C" || l == "POSIX" || StringTools.startsWith(l, "C.")) continue;
			var dot = l.indexOf(".");
			if (dot >= 0) l = l.substr(0, dot);
			var at = l.indexOf("@");
			if (at >= 0) l = l.substr(0, at);
			return l;
		}
		return "en_US";
	}

	// the words of text to check: start and end pairs (UTF-16): runs of
	// letters, an apostrophe inside one; those with a digit (or CJK) left out
	public static function words(text:String):Array<Int> {
		var out = [], i = 0, n = text.length;
		while (i < n) {
			while (i < n && !letter(StringTools.fastCodeAt(text, i)))
				i++;
			if (i >= n) break;
			var s = i, skip = false;
			while (i < n) {
				var c = StringTools.fastCodeAt(text, i);
				// (CJK's ideographs, kana and Hangul: no words a spellchecker has)
				if (c >= 0x2E80 && c < 0xA000 || c >= 0xAC00 && c < 0xD7B0) skip = true;
				if (letter(c)) i++ else if (c >= "0".code && c <= "9".code || c == "_".code) {
					skip = true;
					i++;
				} else if ((c == "'".code || c == 0x2019) && i + 1 < n && letter(StringTools.fastCodeAt(text, i + 1))) i += 2 else break;
			}
			if (!skip) {
				out.push(s);
				out.push(i);
			}
		}
		return out;
	}

	// the misspelled words of text, start and end pairs (each word's answer kept in cache)
	public static function misspelled(c:SpellChecker, text:String, ?cache:Map<String, Bool>):Array<Int> {
		var w = words(text), out = [];
		var k = 0;
		while (k < w.length) {
			var word = text.substring(w[k], w[k + 1]);
			var ok = cache == null ? null : cache.get(word);
			if (ok == null) {
				ok = word.length < 2 || c.check(word);
				if (cache != null) cache.set(word, ok);
			}
			if (!ok) {
				out.push(w[k]);
				out.push(w[k + 1]);
			}
			k += 2;
		}
		return out;
	}

	// (a letter: ASCII's, Latin-1's and every other character above but
	// punctuation, spaces and symbols' common blocks; surrogates (emoji and
	// the like) are not)
	static function letter(c:Int):Bool {
		if (c < 0x80) return c >= "a".code && c <= "z".code || c >= "A".code && c <= "Z".code;
		if (c < 0xC0) return c == 0xAA || c == 0xB5 || c == 0xBA;
		if (c == 0xD7 || c == 0xF7) return false;
		if (c >= 0x2000 && c < 0x2C00) return false; // (punctuation, symbols, arrows, shapes)
		if (c >= 0x3000 && c < 0x3040) return false; // (CJK punctuation)
		if (c >= 0xD800 && c < 0xE000) return false;
		if (c >= 0xFE00 && c < 0xFE10 || c >= 0xFF00 && c < 0xFF10) return false;
		return true;
	}
}
