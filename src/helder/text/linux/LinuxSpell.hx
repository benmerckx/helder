package helder.text.linux;

import helder.text.Spell;
import hxmc.unsafe.*;

// Linux's spellchecker (helder.text.Spell): Enchant (libenchant-2, loaded
// at run time: the broker's dictionary for the language, its providers'
// words and the user's personal dictionary, which add writes to), else
// Hunspell (libhunspell-1.7, its dictionary from /usr/share/hunspell or
// /usr/share/myspell: words added kept for the run). Neither: null.
class LinuxSpell {
	public static function create(lang:String):Null<SpellChecker> {
		var e = EnchantChecker.make(lang);
		if (e != null) return e;
		return HunspellChecker.make(lang);
	}

	// a C array of UTF-8 strings, n of them
	public static function strings(list:Ptr<Ptr>, n:Int):Array<String>
		return [for (i in 0...n) (cast list[i] : CString).toString()];
}

class EnchantChecker implements SpellChecker {
	static var loaded = 0; // (0: not tried, 1: there, -1: none)
	static var broker = Ptr.nil();

	public var language(default, null):String;

	final dict:Ptr;

	public static function make(lang:String):Null<EnchantChecker> {
		if (loaded == 0) {
			loaded = -1;
			for (p in ["libenchant-2.so.2", "libenchant-2.so"])
				if (Enchant.load(p) == null) {
					broker = Enchant.enchant_broker_init();
					if (!broker.isNull()) loaded = 1;
					break;
				}
		}
		if (loaded < 0) return null;
		for (t in Spell.tags(lang)) {
			var d = Arena.scopedValue(a -> {
				var tag = a.cstring(t);
				Enchant.enchant_broker_dict_exists(broker, tag) != 0 ? Enchant.enchant_broker_request_dict(broker, tag) : Ptr.nil();
			});
			if (!d.isNull()) return new EnchantChecker(d, t);
		}
		return null;
	}

	function new(dict:Ptr, language:String) {
		this.dict = dict;
		this.language = language;
	}

	public function check(word:String):Bool
		return Arena.scopedValue(a -> Enchant.enchant_dict_check(dict, a.cstring(word), -1) == 0);

	public function suggest(word:String):Array<String>
		return Arena.scopedValue(a -> {
			var n:Ptr<Int64> = a.alloc(8);
			n.value = 0;
			var list:Ptr<Ptr> = Enchant.enchant_dict_suggest(dict, a.cstring(word), -1, cast n);
			if (list.isNull()) [] else {
				var out = LinuxSpell.strings(list, n.value.toInt());
				Enchant.enchant_dict_free_string_list(dict, list);
				out;
			}
		});

	public function add(word:String)
		Arena.scoped(a -> Enchant.enchant_dict_add(dict, a.cstring(word), -1));
}

class HunspellChecker implements SpellChecker {
	static var loaded = 0;

	public var language(default, null):String;

	final h:Ptr;

	public static function make(lang:String):Null<HunspellChecker> {
		if (loaded == 0) {
			loaded = -1;
			for (p in ["libhunspell-1.7.so.0", "libhunspell.so"])
				if (Hunspell.load(p) == null) {
					loaded = 1;
					break;
				}
		}
		if (loaded < 0) return null;
		for (t in Spell.tags(lang))
			for (dir in ["/usr/share/hunspell", "/usr/share/myspell", "/usr/share/myspell/dicts"]) {
				var aff = '$dir/$t.aff', dic = '$dir/$t.dic';
				if (!sys.FileSystem.exists(aff) || !sys.FileSystem.exists(dic)) continue;
				var h = Arena.scopedValue(a -> Hunspell.Hunspell_create(a.cstring(aff), a.cstring(dic)));
				if (!h.isNull()) return new HunspellChecker(h, t);
			}
		return null;
	}

	function new(h:Ptr, language:String) {
		this.h = h;
		this.language = language;
	}

	public function check(word:String):Bool
		return Arena.scopedValue(a -> Hunspell.Hunspell_spell(h, a.cstring(word)) != 0);

	public function suggest(word:String):Array<String>
		return Arena.scopedValue(a -> {
			var list:Ptr<Ptr> = a.alloc(8);
			list.value = Ptr.nil();
			var n = Hunspell.Hunspell_suggest(h, cast list, a.cstring(word));
			if (n <= 0 || list.value.isNull()) [] else {
				var out = LinuxSpell.strings(cast list.value, n);
				Hunspell.Hunspell_free_list(h, cast list, n);
				out;
			}
		});

	public function add(word:String)
		Arena.scoped(a -> Hunspell.Hunspell_add(h, a.cstring(word)));
}

@:build(helder.os.Dl.build())
class Enchant {
	static function enchant_broker_init():Ptr;
	static function enchant_broker_dict_exists(broker:Ptr, tag:Ptr):Int;
	static function enchant_broker_request_dict(broker:Ptr, tag:Ptr):Ptr;
	static function enchant_dict_check(dict:Ptr, word:Ptr, len:Int64):Int;
	static function enchant_dict_suggest(dict:Ptr, word:Ptr, len:Int64, n:Ptr):Ptr;
	static function enchant_dict_free_string_list(dict:Ptr, list:Ptr):Void;
	static function enchant_dict_add(dict:Ptr, word:Ptr, len:Int64):Void;
}

@:build(helder.os.Dl.build())
class Hunspell {
	static function Hunspell_create(aff:Ptr, dic:Ptr):Ptr;
	static function Hunspell_spell(h:Ptr, word:Ptr):Int;
	static function Hunspell_suggest(h:Ptr, list:Ptr, word:Ptr):Int;
	static function Hunspell_free_list(h:Ptr, list:Ptr, n:Int):Void;
	static function Hunspell_add(h:Ptr, word:Ptr):Int;
}
