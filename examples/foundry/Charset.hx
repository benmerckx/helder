import Model;

// The characters Foundry makes, in groups, and what each borrows until it
// is drawn: mirror images and turns of a drawn letter (b, p and q from d,
// u from n, 6 from 9), capitals grown from small letters whose shape they
// share (o to O, s to S), punctuation from punctuation, and every accented
// letter from its letter and its accent.
class Charset {
	public static final groups:Array<{name:String, chars:Array<String>}> = [
		{name: "Lowercase", chars: split("abcdefghijklmnopqrstuvwxyz")},
		{name: "Uppercase", chars: split("ABCDEFGHIJKLMNOPQRSTUVWXYZ")},
		{name: "Figures", chars: split("0123456789")},
		{name: "Punctuation", chars: split(".,:;!?'\"-()/&@")},
		{name: "Accents", chars: ["´", "`", "ˆ", "¨", "˜", "¸", "ı"]},
		{name: "Accented", chars: split("áàâäéèêëíìîïóòôöúùûüñçÁÀÂÄÉÈÊËÍÌÎÏÓÒÔÖÚÙÛÜÑÇ")}
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

	static final ACCENTS:Map<String, String> = [
		"á" => "a´", "à" => "a`", "â" => "aˆ", "ä" => "a¨", "é" => "e´", "è" => "e`", "ê" => "eˆ", "ë" => "e¨", "í" => "ı´", "ì" => "ı`", "î" => "ıˆ",
		"ï" => "ı¨", "ó" => "o´", "ò" => "o`", "ô" => "oˆ", "ö" => "o¨", "ú" => "u´", "ù" => "u`", "û" => "uˆ", "ü" => "u¨", "ñ" => "n˜", "ç" => "c¸",
		"Á" => "A´", "À" => "A`", "Â" => "Aˆ", "Ä" => "A¨", "É" => "E´", "È" => "E`", "Ê" => "Eˆ", "Ë" => "E¨", "Í" => "I´", "Ì" => "I`", "Î" => "Iˆ",
		"Ï" => "I¨", "Ó" => "O´", "Ò" => "O`", "Ô" => "Oˆ", "Ö" => "O¨", "Ú" => "U´", "Ù" => "U`", "Û" => "Uˆ", "Ü" => "U¨", "Ñ" => "N˜", "Ç" => "C¸"
	];

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
		"ı" => [[{of: "i", how: Dotless}]]
	];

	// what char borrows while it is not drawn: [] when nothing it could borrow from is drawn
	public static function borrow(face:Face, char:String):Array<Part> {
		var accent = ACCENTS.get(char);
		if (accent != null) {
			var base = accent.charAt(0), mark = accent.substr(1);
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
		for (g in groups)
			if (g.chars.indexOf(char) >= 0) return switch g.name {
				case "Uppercase": "H";
				case "Figures": "0";
				case _: "n";
			}
		return "n";
	}

	// whether char stands as tall as a capital (its guides, a part's turns)
	public static function tall(char:String):Bool
		return groups[1].chars.indexOf(char) >= 0 || groups[2].chars.indexOf(char) >= 0;

	public static function code(char:String):Int
		return new haxe.iterators.StringIteratorUnicode(char).next();

	static function split(s:String):Array<String>
		return [for (c in new haxe.iterators.StringIteratorUnicode(s)) String.fromCharCode(c)];
}
