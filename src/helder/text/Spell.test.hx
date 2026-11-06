package helder.text;

import helder.test.Test;

// helder.text.Spell: the words a text is checked by (letters, an
// apostrophe inside, digits' words left out), the misspelled ones through
// a checker of the test's and its cache, the deterministic switch (helder
// test's text engine: no system checker); the platform's own checker is
// tests/text/SpellTest.hx's (the window lane, each desktop).
class FakeChecker implements SpellChecker {
	public var language(default, null) = "en_US";
	public var asked:Array<String> = [];

	final known = ["the", "quick", "fox", "don't", "café"];

	public function new() {}

	public function check(word:String):Bool {
		asked.push(word);
		return known.indexOf(word.toLowerCase()) >= 0;
	}

	public function suggest(word:String):Array<String>
		return [for (k in known) if (k.charAt(0) == word.charAt(0).toLowerCase()) k];

	public function add(word:String)
		known.push(word.toLowerCase());
}

function tests() {
	describe("Spell", () -> {
		test("words: letters, an apostrophe inside, not digits' words", () -> {
			var t = "The quick, don't 'fox' x2 café—naïve";
			var w = Spell.words(t);
			equals([for (k in 0...w.length >> 1) t.substring(w[2 * k], w[2 * k + 1])], ["The", "quick", "don't", "fox", "café", "naïve"]);
			equals(Spell.words("  42  "), []);
		});
		test("misspelled: start and end pairs, each word asked once", () -> {
			var c = new FakeChecker(), cache = new Map();
			var t = "The quikc fox jmups, the quikc fox";
			var m = Spell.misspelled(c, t, cache);
			equals([for (k in 0...m.length >> 1) t.substring(m[2 * k], m[2 * k + 1])], ["quikc", "jmups", "quikc"]);
			equals(c.asked, ["The", "quikc", "fox", "jmups", "the"]);
			c.add("jmups");
			cache.clear();
			equals(Spell.misspelled(c, "jmups", cache), []);
		});
		test("the deterministic text engine: no system checker", () -> {
			if (Shaping.engine == Shaping.HELDER) equals(Spell.checker(), null);
			var f = new FakeChecker();
			Spell.given = f;
			equals(Spell.checker(), f);
			Spell.given = null;
		});
		test("the language: LANG's tag", () -> {
			var saved = [for (v in ["LC_ALL", "LC_MESSAGES", "LANG"]) v => Sys.getEnv(v)];
			Sys.putEnv("LC_ALL", "");
			Sys.putEnv("LC_MESSAGES", "");
			Sys.putEnv("LANG", "nl_BE.UTF-8");
			equals(Spell.language(), "nl_BE");
			equals(Spell.tags("nl_BE"), ["nl_BE", "nl", "en_US", "en"]);
			for (k => v in saved)
				Sys.putEnv(k, v ?? "");
		});
	});
}
