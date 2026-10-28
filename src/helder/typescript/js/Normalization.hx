package helder.typescript.js;

import helder.typescript.js.unicode.NormalizationData;

// UAX #15: recursive decomposition, canonical ordering and blocked composition.
// UTF-16 lone surrogates pass through, as required by String.normalize.
class Normalization {
	static var decompositions:Map<Int, Array<Int>>;
	static var compatibility:Map<Int, Bool>;
	static var combining:Map<Int, Int>;
	static var compositions:Map<Int, Map<Int, Int>>;
	static function hex(s:String):Int return Std.parseInt("0x" + s);

	static function init():Void {
		if (decompositions != null) return;
		decompositions = [];
		compatibility = [];
		combining = [];
		compositions = [];
		for (record in NormalizationData.decompositions().split(";")) {
			var fields = record.split(":"), cp = hex(fields[0]);
			decompositions.set(cp, [for (x in fields[2].split(",")) hex(x)]);
			if (fields[1] == "k") compatibility.set(cp, true);
		}
		for (record in NormalizationData.combining().split(";")) {
			var fields = record.split(":");
			combining.set(hex(fields[0]), hex(fields[1]));
		}
		for (record in NormalizationData.compositions().split(";")) {
			var fields = record.split(":"), pair = fields[0].split(","), first = hex(pair[0]);
			if (!compositions.exists(first)) compositions.set(first, []);
			compositions.get(first).set(hex(pair[1]), hex(fields[1]));
		}
	}

	static function ccc(cp:Int):Int return combining.exists(cp) ? combining.get(cp) : 0;

	static function append(cp:Int, out:Array<Int>):Void {
		var order = ccc(cp);
		out.push(cp);
		if (order == 0) return;
		var i = out.length - 1;
		while (i > 0 && ccc(out[i - 1]) > order) {
			out[i] = out[i - 1];
			i--;
		}
		out[i] = cp;
	}

	static function decompose(cp:Int, compat:Bool, out:Array<Int>):Void {
		var syllable = cp - 0xac00;
		if (syllable >= 0 && syllable < 11172) {
			append(0x1100 + Std.int(syllable / 588), out);
			append(0x1161 + Std.int(syllable % 588 / 28), out);
			var trail = syllable % 28;
			if (trail != 0) append(0x11a7 + trail, out);
		}
		else if (decompositions.exists(cp) && (compat || !compatibility.exists(cp)))
			for (part in decompositions.get(cp)) decompose(part, compat, out);
		else append(cp, out);
	}

	static function compose(first:Int, second:Int):Int {
		var l = first - 0x1100, v = second - 0x1161;
		if (l >= 0 && l < 19 && v >= 0 && v < 21) return 0xac00 + (l * 21 + v) * 28;
		var syllable = first - 0xac00, t = second - 0x11a7;
		if (syllable >= 0 && syllable < 11172 && syllable % 28 == 0 && t > 0 && t < 28) return first + t;
		var table = compositions.get(first);
		return table != null && table.exists(second) ? table.get(second) : -1;
	}

	public static function normalize(value:String, form:String):String {
		init();
		var compat = form == "NFKC" || form == "NFKD", composeResult = form == "NFC" || form == "NFKC";
		var points:Array<Int> = [], i = 0;
		while (i < value.length) {
			var cp = value.charCodeAt(i++);
			if (cp >= 0xd800 && cp <= 0xdbff && i < value.length) {
				var low = value.charCodeAt(i);
				if (low >= 0xdc00 && low <= 0xdfff) {
					i++;
					cp = 0x10000 + ((cp - 0xd800) << 10) + (low - 0xdc00);
				}
			}
			decompose(cp, compat, points);
		}
		if (composeResult && points.length > 0) {
			var out = [points[0]], starter = points[0], at = 0, last = ccc(points[0]);
			for (i in 1...points.length) {
				var cp = points[i], order = ccc(cp), combined = compose(starter, cp);
				if (combined >= 0 && (last == 0 || last < order)) {
					out[at] = combined;
					starter = combined;
				}
				else {
					if (order == 0) {
						at = out.length;
						starter = cp;
					}
					out.push(cp);
					last = order;
				}
			}
			points = out;
		}
		var result = new StringBuf();
		for (cp in points) if (cp < 65536) result.addChar(cp); else {
			var v = cp - 0x10000;
			result.addChar(0xd800 + (v >> 10));
			result.addChar(0xdc00 + (v & 1023));
		}
		return result.toString();
	}
}
