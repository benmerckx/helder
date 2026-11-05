package helder.text;

// Unicode's canonical compositions of a character and the mark after it
// (helder.text.unicode.NormalizationData's, the pairs NFC composes; Hangul's
// syllables left out): what HarfBuzz composes when the font has the
// composed character
class Compose {
	// (the character => the mark => the composition)
	static var table:Null<Map<Int, Map<Int, Int>>> = null;

	// the composition of a and mark (0: none)
	public static function pair(a:Int, mark:Int):Int {
		if (table == null) {
			table = new Map();
			// ("41,300:c0": the character, the mark, the composition, in hex)
			for (record in helder.text.unicode.NormalizationData.compositions().split(";")) {
				var colon = record.indexOf(":"), comma = record.indexOf(",");
				var first = Std.parseInt("0x" + record.substring(0, comma)), second = Std.parseInt("0x" + record.substring(comma + 1, colon));
				var marks = table.get(first);
				if (marks == null) table.set(first, marks = new Map());
				marks.set(second, Std.parseInt("0x" + record.substr(colon + 1)));
			}
		}
		var marks = table.get(a);
		var c = marks == null ? null : marks.get(mark);
		return c == null ? 0 : c;
	}
}
