package helder.text.windows;

import helder.text.Spell;
import helder.os.win32.Com;
import hxmc.unsafe.*;

// Windows' spellchecker (Windows 8 and later; helder.text.Spell):
// ISpellCheckerFactory (CoCreateInstance of the SpellCheckerFactory class)
// made the language's ISpellChecker (its tag as BCP 47's: en-US), a word
// checked by Check (no ISpellingError from its enumerator: right),
// suggestions by Suggest (an IEnumString), a word added by Add (the user's
// dictionary, which the checker reads again later) and Ignore (right at once). No factory (Wine, older systems) or no checker for the
// language nor English: null.
@:hxmc.unsafe(gc)
class WinSpell implements SpellChecker {
	static final CLSID_FACTORY = Com.guid(0x7AB36653, 0x1796, 0x484B, [0xBD, 0xFA, 0xE7, 0x4F, 0x1D, 0xB7, 0xC1, 0xDC]);
	static final IID_FACTORY = Com.guid(0x8E018A9D, 0x2415, 0x4677, [0xBF, 0x08, 0x79, 0x4E, 0xA6, 0x1F, 0x94, 0xBB]);

	public var language(default, null):String;

	final checker:Ptr;

	public static function create(lang:String):Null<SpellChecker> {
		Ole.CoInitializeEx(Ptr.nil(), 2); // (COINIT_APARTMENTTHREADED; already: S_FALSE)
		var f = out(p -> Ole.CoCreateInstance(CLSID_FACTORY, Ptr.nil(), 1, IID_FACTORY, p));
		if (f.isNull()) return null;
		var made:Null<SpellChecker> = null;
		for (t in helder.text.Spell.tags(lang)) {
			var tag = StringTools.replace(t, "_", "-");
			var ok = Arena.scopedValue(a -> {
				var b:Ptr<Int32> = a.alloc(4);
				b.value = 0;
				ISpellCheckerFactory.IsSupported(f, a.wstring(tag), b) >= 0 && b.value != 0;
			});
			if (!ok) continue;
			var c = Arena.scopedValue(a -> {
				var w = a.wstring(tag);
				out(p -> ISpellCheckerFactory.CreateSpellChecker(f, w, p));
			});
			if (!c.isNull()) {
				made = new WinSpell(c, tag);
				break;
			}
		}
		Com.release(f);
		return made;
	}

	function new(checker:Ptr, language:String) {
		this.checker = checker;
		this.language = language;
	}

	public function check(word:String):Bool
		return Arena.scopedValue(a -> {
			var w = a.wstring(word);
			var errors = out(p -> ISpellChecker.Check(checker, w, p));
			if (errors.isNull()) true else {
				var e = out(p -> IEnumSpellingError.Next(errors, p));
				Com.release(errors);
				if (e.isNull()) true else {
					Com.release(e);
					false;
				}
			}
		});

	public function suggest(word:String):Array<String>
		return Arena.scopedValue(a -> {
			var w = a.wstring(word), list = [];
			var e = out(p -> ISpellChecker.Suggest(checker, w, p));
			if (!e.isNull()) {
				var s:Ptr<Ptr> = a.alloc(8), n:Ptr<Int32> = a.alloc(4);
				// (S_OK 0: one more; S_FALSE 1: none)
				while (true) {
					s.value = Ptr.nil();
					n.value = 0;
					if (IEnumString.Next(e, 1, s, n) != 0 || n.value == 0 || s.value.isNull()) break;
					list.push(wide(s.value));
					Ole.CoTaskMemFree(s.value);
				}
				Com.release(e);
			}
			list;
		});

	// (Add: the user's dictionary, which the checker reads again later; Ignore: right at once, for the run)
	public function add(word:String)
		Arena.scoped(a -> {
			var w = a.wstring(word);
			ISpellChecker.Add(checker, w);
			ISpellChecker.Ignore(checker, w);
		});

	static function wide(p:Ptr<UInt16>):String {
		var b = new StringBuf(), i = 0;
		while (p[i] != 0) {
			var c:Int = p[i++];
			if (c >= 0xD800 && c < 0xDC00 && p[i] >= 0xDC00 && p[i] < 0xE000) c = 0x10000 + ((c - 0xD800) << 10) + ((p[i++] : Int) - 0xDC00);
			b.addChar(c);
		}
		return b.toString();
	}

	// (a COM call's out pointer: its value, nil when it failed)
	static function out(f:Ptr<Ptr>->Int):Ptr {
		var p:Ptr<Ptr> = LibC.malloc(8);
		p.value = Ptr.nil();
		var hr = f(p);
		var v = p.value;
		LibC.free(cast p);
		return hr < 0 ? Ptr.nil() : v;
	}
}

@:hxmc.c @:hxmc.lib("ole32") extern class Ole {
	static function CoInitializeEx(reserved:Ptr, flags:Int):Int;
	static function CoCreateInstance(clsid:Ptr, outer:Ptr, context:Int, iid:Ptr, out:Ptr<Ptr>):Int;
	static function CoTaskMemFree(p:Ptr):Void;
}

// (IUnknown's three, then get_SupportedLanguages, IsSupported, CreateSpellChecker)
@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class ISpellCheckerFactory {
	@:slot(4) static function IsSupported(self:Ptr, tag:Ptr, out:Ptr<Int32>):Int;
	@:slot(5) static function CreateSpellChecker(self:Ptr, tag:Ptr, out:Ptr<Ptr>):Int;
}

// (get_LanguageTag 3, Check 4, Suggest 5, Add 6, Ignore 7, AutoCorrect 8, ...)
@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class ISpellChecker {
	@:slot(4) static function Check(self:Ptr, text:Ptr, out:Ptr<Ptr>):Int;
	@:slot(5) static function Suggest(self:Ptr, word:Ptr, out:Ptr<Ptr>):Int;
	@:slot(6) static function Add(self:Ptr, word:Ptr):Int;
	@:slot(7) static function Ignore(self:Ptr, word:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IEnumSpellingError {
	@:slot(3) static function Next(self:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IEnumString {
	@:slot(3) static function Next(self:Ptr, count:Int, out:Ptr<Ptr>, fetched:Ptr<Int32>):Int;
}
