import helder.text.Spell;
import helder.text.SpellChecker;
import hxmc.Platform;
import hxmc.unsafe.*;

// The platform's spellchecker (helder.text.Spell; the window lane, natively
// on each desktop, Windows also under Wine): made for English, a right word
// and a wrong one, suggestions for the wrong one (the right among them), a
// word added to the user's dictionary right from then (Linux: Enchant's
// personal dictionary in a directory of the test's, XDG_CONFIG_HOME;
// Hunspell's for the run). Where the system has none (Linux without
// Enchant or Hunspell's dictionaries, Wine): said, spellcheck off. On macOS
// and Windows one is required. HELDER_NO_SPELLCHECK=1 and helder's own text
// engine turn Spell.checker() off.
//   SpellTest [dir]
class SpellTest {
	static var failed = 0;

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println('SpellTest: ${ok ? "ok" : "FAIL"}: $what${detail == "" ? "" : " (" + detail + ")"}');
		if (!ok) failed++;
	}

	// (under Wine: ntdll's wine_get_version)
	static function wine():Bool
		return Platform.os() == 2 ? Arena.scopedValue(a -> !K32.GetProcAddress(K32.GetModuleHandleW(a.wstring("ntdll.dll")), a.cstring("wine_get_version")).isNull()) : false;

	static function checks(c:SpellChecker, w:String) {
		var name = Type.getClassName(Type.getClass(c));
		Sys.println('SpellTest: $name, ${c.language}');
		check('$name: a right word', c.check("hello") && c.check("language"));
		check('$name: a wrong word', !c.check("brwon") && !c.check("langauge"));
		var s = c.suggest("langauge");
		check('$name: suggestions for it, the right among them', s.indexOf("language") >= 0, s.join(", "));
		var before = c.check(w);
		c.add(w);
		var after = c.check(w);
		check('$name: a word added: right from then', !before && after, 'before $before, after $after');
		var m = Spell.misspelled(c, "The quick brwon fox");
		check('$name: misspelled: the wrong word\'s place', m.join(",") == "10,15", m.join(","));
	}

	static function remove(path:String) {
		if (sys.FileSystem.isDirectory(path)) {
			for (f in sys.FileSystem.readDirectory(path))
				remove(path + "/" + f);
			sys.FileSystem.deleteDirectory(path);
		} else sys.FileSystem.deleteFile(path);
	}

	static function main() {
		var dir = Sys.args().length > 0 ? Sys.args()[0] : "bin/text";
		var conf = "";
		if (Platform.os() == 0) {
			// (the personal dictionary the test's own, a new directory each run)
			conf = sys.FileSystem.fullPath(dir) + "/spell-config-" + Std.int(haxe.Timer.stamp() * 1000) % 100000000;
			sys.FileSystem.createDirectory(conf);
			Sys.putEnv("XDG_CONFIG_HOME", conf);
			// (aspell, an Enchant provider: its word list in HOME)
			Sys.putEnv("HOME", conf);
		}
		var c:Null<SpellChecker> = Spell.platform("en_US");
		var required = Platform.os() == 1 || Platform.os() == 2 && !wine();
		if (c == null) {
			Sys.println("SpellTest: no spellchecker here" + (Platform.os() == 0 ? " (no libenchant-2 nor Hunspell with an English dictionary)" : wine() ? " (Wine has no ISpellCheckerFactory)" : "") + ": spellcheck off");
			check("a spellchecker on this system", !required);
		} else checks(c, "xqzvhelderb");
		// (Linux: Hunspell's own, Enchant's fallback, where it is there)
		if (Platform.os() == 0 && Platform.target() < 9) {
			var h:Null<SpellChecker> = helder.text.linux.LinuxSpell.HunspellChecker.make("en_US");
			if (h == null) Sys.println("SpellTest: no Hunspell with an English dictionary: its fallback not checked") else checks(h, "xqzvhelderc");
		}
		// (the switches: helder's text engine, HELDER_NO_SPELLCHECK)
		helder.text.Shaping.engine = helder.text.Shaping.HELDER;
		check("the deterministic text engine: Spell.checker() off", Spell.checker() == null);
		if (conf != "") remove(conf);
		Sys.println('SpellTest: ' + (failed == 0 ? "ok" : '$failed FAILED'));
		Sys.exit(failed > 0 ? 1 : 0);
	}
}

@:hxmc.c @:hxmc.fast @:hxmc.lib("kernel32") extern class K32 {
	static function GetModuleHandleW(name:Ptr):Ptr;
	static function GetProcAddress(module:Ptr, name:Ptr):Ptr;
}
