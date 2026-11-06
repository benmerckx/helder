package helder.text.mac;

import helder.text.Spell;
import helder.os.objc.ObjC;
import helder.os.objc.Msg;
import hxmc.unsafe.*;

// macOS's spellchecker (helder.text.Spell): NSSpellChecker's shared one, in
// the language asked where it has it (setLanguage:, a tag as en_US), else
// its own choice; a word checked by checkString:range:types:... for
// spelling (no result: right), suggestions by
// guessesForWordRange:inString:language:inSpellDocumentWithTag:, a word
// learnt by learnWord: (the user's dictionary).
class MacSpell implements SpellChecker {
	public var language(default, null):String;

	final checker:Ptr;

	public static function create(lang:String):Null<SpellChecker> {
		// (AppKit loaded: a program without a window has not yet)
		helder.os.cocoa.CocoaWindow.AppKit.NSApplicationLoad();
		var c = Msg.id(ObjC.cls("NSSpellChecker"), ObjC.sel("sharedSpellChecker"));
		if (c.isNull()) return null;
		var chosen:Null<String> = null;
		for (t in helder.text.Spell.tags(lang)) {
			var s = ObjC.str(t);
			var ok = Msg.bPtr(c, ObjC.sel("setLanguage:"), s);
			ObjC.release(s);
			if (ok) {
				chosen = t;
				break;
			}
		}
		if (chosen == null) chosen = ObjC.string(Msg.id(c, ObjC.sel("language"))) ?? lang;
		return new MacSpell(c, chosen);
	}

	function new(checker:Ptr, language:String) {
		this.checker = checker;
		this.language = language;
	}

	public function check(word:String):Bool {
		var s = ObjC.str(word);
		// (NSTextCheckingTypeSpelling 2; no options, tag 0, no orthography or word count)
		var results = Msg.idPtrIntIntIntPtrIntPtrPtr(checker, ObjC.sel("checkString:range:types:options:inSpellDocumentWithTag:orthography:wordCount:"), s, 0,
			word.length, 2, Ptr.nil(), 0, Ptr.nil(), Ptr.nil());
		var n = results.isNull() ? 0 : Msg.i(results, ObjC.sel("count"));
		ObjC.release(s);
		return n == 0;
	}

	public function suggest(word:String):Array<String> {
		var s = ObjC.str(word), l = ObjC.str(language);
		var a = Msg.idIntIntPtrPtrInt(checker, ObjC.sel("guessesForWordRange:inString:language:inSpellDocumentWithTag:"), 0, word.length, s, l, 0);
		var out = [];
		if (!a.isNull()) {
			var n = Msg.i(a, ObjC.sel("count")).toInt();
			for (i in 0...n) {
				var g = ObjC.string(Msg.idInt(a, ObjC.sel("objectAtIndex:"), i));
				if (g != null) out.push(g);
			}
		}
		ObjC.release(s);
		ObjC.release(l);
		return out;
	}

	public function add(word:String) {
		var s = ObjC.str(word);
		Msg.vPtr(checker, ObjC.sel("learnWord:"), s);
		ObjC.release(s);
	}
}
