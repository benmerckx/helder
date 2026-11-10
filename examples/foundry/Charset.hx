import Model;

// The characters Foundry makes, in groups, and what each borrows until it
// is drawn: mirror images and turns of a drawn letter (b, p and q from d,
// u from n, 6 from 9), capitals grown from small letters whose shape they
// share (o to O, s to S), punctuation from punctuation, and every accented
// letter from its letter and its accent.
class Charset {
	// Unicode's decompositions of Latin-1's and Latin Extended-A's letters into a
	// letter and a mark (the mark as its spacing form; i and j without their dots)
	static final DECOMPOSED = "ÀA`|ÁA´|ÂAˆ|ÃA˜|ÄA¨|ÅA˚|ÇC¸|ÈE`|ÉE´|ÊEˆ|ËE¨|ÌI`|ÍI´|ÎIˆ|ÏI¨|ÑN˜|ÒO`|ÓO´|ÔOˆ|ÕO˜|ÖO¨|ÙU`|ÚU´|ÛUˆ|ÜU¨|ÝY´|àa`|áa´|âaˆ|ãa˜|äa¨|åa˚|çc¸|èe`|ée´|êeˆ|ëe¨|ìı`|íı´|îıˆ|ïı¨|ñn˜|òo`|óo´|ôoˆ|õo˜|öo¨|ùu`|úu´|ûuˆ|üu¨|ýy´|ÿy¨|ĀA¯|āa¯|ĂA˘|ăa˘|ĄA˛|ąa˛|ĆC´|ćc´|ĈCˆ|ĉcˆ|ĊC˙|ċc˙|ČCˇ|čcˇ|ĎDˇ|ďdˇ|ĒE¯|ēe¯|ĔE˘|ĕe˘|ĖE˙|ėe˙|ĘE˛|ęe˛|ĚEˇ|ěeˇ|ĜGˆ|ĝgˆ|ĞG˘|ğg˘|ĠG˙|ġg˙|ĢG¸|ģg¸|ĤHˆ|ĥhˆ|ĨI˜|ĩı˜|ĪI¯|īı¯|ĬI˘|ĭı˘|ĮI˛|įı˛|İI˙|ĴJˆ|ĵȷˆ|ĶK¸|ķk¸|ĹL´|ĺl´|ĻL¸|ļl¸|ĽLˇ|ľlˇ|ŃN´|ńn´|ŅN¸|ņn¸|ŇNˇ|ňnˇ|ŌO¯|ōo¯|ŎO˘|ŏo˘|ŐO˝|őo˝|ŔR´|ŕr´|ŖR¸|ŗr¸|ŘRˇ|řrˇ|ŚS´|śs´|ŜSˆ|ŝsˆ|ŞS¸|şs¸|ŠSˇ|šsˇ|ŢT¸|ţt¸|ŤTˇ|ťtˇ|ŨU˜|ũu˜|ŪU¯|ūu¯|ŬU˘|ŭu˘|ŮU˚|ůu˚|ŰU˝|űu˝|ŲU˛|ųu˛|ŴWˆ|ŵwˆ|ŶYˆ|ŷyˆ|ŸY¨|ŹZ´|źz´|ŻZ˙|żz˙|ŽZˇ|žzˇ|ȘȘ|șș|ȚȚ|țț";

	public static final groups:Array<{name:String, chars:Array<String>}> = [
		{name: "Lowercase", chars: split("abcdefghijklmnopqrstuvwxyz")},
		{name: "Uppercase", chars: split("ABCDEFGHIJKLMNOPQRSTUVWXYZ")},
		{name: "Figures", chars: split("0123456789")},
		{name: "Punctuation", chars: split(".,:;!?'\"-()/&@¡¿")},
		{name: "Accents", chars: ["´", "`", "ˆ", "¨", "˜", "¯", "˘", "˙", "˚", "˝", "ˇ", "¸", "˛", "\u0326", "ı", "ȷ"]},
		{name: "Special letters", chars: split("æœøßłđħþðÆŒØŁĐĦÞÐ")},
		{name: "Accented", chars: [for (e in DECOMPOSED.split("|")) firstOf(e)]}
	];

	public static final all:Array<String> = [for (g in groups) for (c in g.chars) c];

	// the letters to draw first, in order: each one sets something the
	// rest follow (n: stems and arches, o: bowls, H and O: capitals...)
	public static final start = ["n", "o", "H", "O", "i", "a", "e", "s"];

	// what each start letter teaches
	public static final why:Map<String, String> = [
		"n" => "Stems and arches. h, m, r and u grow from it.",
		"o" => "The round shape. b, c, d, e, p and q share it.",
		"H" => "Capital stems and how tall capitals stand.",
		"O" => "The round capital: C, G, Q follow it.",
		"i" => "The simplest letter: one stem, one dot.",
		"a" => "The first letter of most words.",
		"e" => "The most common letter in English.",
		"s" => "The hardest curve. Take your time."
	];

	static final ACCENTS:Map<String, String> = [for (e in DECOMPOSED.split("|")) firstOf(e) => e.substr(firstOf(e).length)];

	static function firstOf(e:String):String
		return String.fromCharCode(new haxe.iterators.StringIteratorUnicode(e).next());

	// the marks that hang under their letter, and the anchor each takes
	public static function anchorOf(mark:String):String
		return mark == "˛" ? "ogonek" : mark == "¸" || mark == "\u0326" ? "bottom" : "top";

	// a glyph's suggestions, the first whose source is drawn wins
	static final BORROW:Map<String, Array<Array<Part>>> = [
		"b" => [[{of: "d", how: Flip}], [{of: "q", how: Half}], [{of: "p", how: Flop}]],
		"d" => [[{of: "b", how: Flip}], [{of: "p", how: Half}], [{of: "q", how: Flop}]],
		"p" => [[{of: "q", how: Flip}], [{of: "d", how: Half}], [{of: "b", how: Flop}]],
		"q" => [[{of: "p", how: Flip}], [{of: "b", how: Half}], [{of: "d", how: Flop}]],
		"u" => [[{of: "n", how: Half}]],
		"n" => [[{of: "u", how: Half}]],
		"M" => [[{of: "W", how: Flop}]],
		"W" => [[{of: "M", how: Flop}], [{of: "w", how: Grow}]],
		"6" => [[{of: "9", how: Half}]],
		"9" => [[{of: "6", how: Half}]],
		"0" => [[{of: "O", how: Same}]],
		"C" => [[{of: "c", how: Grow}]],
		"O" => [[{of: "o", how: Grow}]],
		"S" => [[{of: "s", how: Grow}]],
		"V" => [[{of: "v", how: Grow}]],
		"X" => [[{of: "x", how: Grow}]],
		"Z" => [[{of: "z", how: Grow}]],
		"I" => [[{of: "l", how: Grow}]],
		"l" => [[{of: "I", how: Same}]],
		")" => [[{of: "(", how: Flip}]],
		"(" => [[{of: ")", how: Flip}]],
		"`" => [[{of: "´", how: Flip}]],
		"´" => [[{of: "`", how: Flip}]],
		":" => [[{of: ".", how: Same}, {of: ".", how: Top}]],
		";" => [[{of: ",", how: Same}, {of: ".", how: Top}]],
		"\"" => [[{of: "'", how: Same}, {of: "'", how: Beside}]],
		"ı" => [[{of: "i", how: Dotless}]],
		"ȷ" => [[{of: "j", how: Dotless}]],
		"¡" => [[{of: "!", how: Half}]],
		"¿" => [[{of: "?", how: Half}]],
		"\u0326" => [[{of: ",", how: Same}]]
	];

	// what char borrows while it is not drawn: [] when nothing it could borrow from is drawn
	public static function borrow(face:Face, char:String):Array<Part> {
		var accent = ACCENTS.get(char);
		if (accent != null) {
			var base = firstOf(accent), mark = accent.substr(base.length);
			return [{of: base, how: Same}, {of: mark, how: Mark}];
		}
		var options = BORROW.get(char);
		if (options == null) return [];
		for (parts in options)
			if (Model.drawn(face, parts[0].of)) return parts;
		return [];
	}

	// the parts a glyph is made of now: its own, else the suggestion
	public static function parts(face:Face, char:String):Array<Part> {
		var g = Model.glyph(face, char);
		return g != null ? g.parts : borrow(face, char);
	}

	// a sentence for what a glyph borrows ("Borrowed from d, mirrored")
	public static function describe(parts:Array<Part>):String {
		if (parts.length == 0) return "";
		if (parts.length == 2 && parts[1].how == Mark) return 'Made from ${parts[0].of} and ${parts[1].of}';
		var p = parts[0];
		var how = switch p.how {
			case Flip: ", mirrored";
			case Half: ", turned around";
			case Flop: ", flipped over";
			case Grow: ", grown to a capital";
			case Dotless: " without its dot";
			case _: parts.length > 1 ? " twice" : "";
		}
		return 'Borrowed from ${p.of}$how';
	}

	// the letter shown either side of char on the board, for its spacing
	public static function neighbour(char:String):String {
		var cp = code(char);
		if (cp >= 0x0410 && cp <= 0x042F) return "Н";
		if (cp >= 0x0430 && cp <= 0x044F) return "н";
		if (cp >= 0x0391 && cp <= 0x03A9) return "Η";
		for (g in groups)
			if (g.chars.indexOf(char) >= 0) return switch g.name {
				case "Uppercase": "H";
				case "Figures": "0";
				case _: "n";
			}
		return "n";
	}

	// whether char stands as tall as a capital (its guides, a part's turns)
	public static function tall(char:String):Bool {
		if (groups[1].chars.indexOf(char) >= 0 || groups[2].chars.indexOf(char) >= 0) return true;
		// (a capital of any script: as tall as the capitals)
		return !unencoded(char) && char.length <= 2 && char.toUpperCase() == char && char.toLowerCase() != char;
	}

	// a key's character (-1: a glyph without one, "#" and its name)
	public static function code(char:String):Int
		return unencoded(char) ? -1 : new haxe.iterators.StringIteratorUnicode(char).next();

	public static inline function unencoded(key:String):Bool
		return key.length > 1 && key.charAt(0) == "#";

	// a face's groups: Foundry's own (what a font is made of), then the
	// rest it has, by kind and script, in Unicode's order; glyphs without
	// a character last
	public static function of(face:Face):Array<{name:String, chars:Array<String>}> {
		if (last != null && last.glyphs == face.glyphs) return last.groups;
		var core = new Map<String, Bool>();
		for (c in all)
			core.set(c, true);
		var more = new Map<String, Array<String>>(), names = [];
		var keys = [for (k in face.glyphs.keys()) if (!core.exists(k)) k];
		keys.sort((a, b) -> {
			var ca = code(a), cb = code(b);
			return ca != cb ? ca - cb : a < b ? -1 : a > b ? 1 : 0;
		});
		for (k in keys) {
			var name = kind(code(k));
			var g = more.get(name);
			if (g == null) {
				more.set(name, g = []);
				names.push(name);
			}
			g.push(k);
		}
		var order = ["Latin Extended", "Greek", "Cyrillic", "Numbers", "More punctuation", "Currency", "Arrows", "Math", "Symbols", "Marks", "Other", "Without a character"];
		names.sort((a, b) -> order.indexOf(a) - order.indexOf(b));
		var groups = groups.concat([for (n in names) {name: n, chars: more.get(n)}]);
		last = {glyphs: face.glyphs, groups: groups};
		return groups;
	}

	static var last:Null<{glyphs:Dynamic, groups:Array<{name:String, chars:Array<String>}>}> = null;

	// every key of a face's groups
	public static function list(face:Face):Array<String>
		return [for (g in of(face)) for (c in g.chars) c];

	static function kind(cp:Int):String
		return if (cp < 0) "Without a character" else if (cp >= 0x0300 && cp <= 0x036F || cp >= 0x02B0 && cp <= 0x02FF) "Marks" else
			if (cp >= 0x00C0 && cp <= 0x024F || cp >= 0x1E00 && cp <= 0x1EFF || cp >= 0x2C60 && cp <= 0x2C7F || cp >= 0xA720 && cp <= 0xA7FF) "Latin Extended" else
			if (cp >= 0x0370 && cp <= 0x03FF || cp >= 0x1F00 && cp <= 0x1FFF) "Greek" else if (cp >= 0x0400 && cp <= 0x052F) "Cyrillic" else
			if (cp >= 0x0030 && cp <= 0x0039 || cp >= 0x00B2 && cp <= 0x00B3 || cp == 0x00B9 || cp >= 0x00BC && cp <= 0x00BE || cp >= 0x2070 && cp <= 0x209F
				|| cp >= 0x2150 && cp <= 0x218F) "Numbers" else if (cp >= 0x20A0 && cp <= 0x20CF || cp == 0x24 || cp >= 0xA2 && cp <= 0xA5) "Currency" else
			if (cp >= 0x2190 && cp <= 0x21FF || cp >= 0x27F0 && cp <= 0x27FF) "Arrows" else
			if (cp >= 0x2200 && cp <= 0x22FF || cp == 0xD7 || cp == 0xF7 || cp == 0xB1 || cp == 0xAC || cp >= 0x2B && cp <= 0x2B || cp >= 0x3C && cp <= 0x3E) "Math" else
			if (cp >= 0x21 && cp <= 0x7E || cp >= 0xA0 && cp <= 0xBF || cp >= 0x2000 && cp <= 0x206F) "More punctuation" else
			if (cp >= 0x2100 && cp <= 0x214F || cp >= 0x2300 && cp <= 0x2BFF || cp >= 0x25A0 && cp <= 0x25FF) "Symbols" else "Other";

	static function split(s:String):Array<String>
		return [for (c in new haxe.iterators.StringIteratorUnicode(s)) String.fromCharCode(c)];
}
