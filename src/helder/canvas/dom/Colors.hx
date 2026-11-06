package helder.canvas.dom;

// CSS colours as Canvas 2D reads and writes them: rgb(), rgba(), hsl()
// and hsla() by CSS Color 4's grammar exactly (the legacy comma form or
// the space form with "/ alpha", never mixed; numbers or percentages as
// each allows; angles in deg, rad, grad, turn; a missing ")" at the end
// closed, as CSS's tokenizer does); names, #hex and the other functions
// by CssColor. Serialized as the browser does (#rrggbb when
// opaque, else rgba(r, g, b, a)).
class Colors {
	public static function parse(s:String):Null<Int> {
		var v = StringTools.trim(s).toLowerCase();
		if (v == "currentcolor") return 0xFF000000;
		var fn = ~/^(rgba?|hsla?)\(/;
		if (fn.match(v)) return func(fn.matched(1), v.substr(fn.matched(0).length));
		if (StringTools.startsWith(v, "var(") || v == "canvas" || v == "canvastext") return null;
		return helder.canvas.CssColor.parse(s);
	}

	// (a token: a number, a percentage, an angle, none, a comma or a slash)
	static final TOKEN = ~/^\s*(?:([-+]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)(?:e[-+]?[0-9]+)?)(%|deg|rad|grad|turn)?|(none)|(,)|(\/))/;

	static function func(name:String, rest:String):Null<Int> {
		var close = rest.lastIndexOf(")");
		var body = close >= 0 ? rest.substr(0, close) : rest;
		if (close >= 0 && StringTools.trim(rest.substr(close + 1)) != "") return null;
		// (the tokens: kinds n number, p percent, a angle, x none, c comma, s slash)
		var kinds:Array<String> = [], values:Array<Float> = [];
		var t = body;
		while (StringTools.trim(t) != "") {
			if (!TOKEN.match(t)) return null;
			if (TOKEN.matched(1) != null) {
				var unit = TOKEN.matched(2);
				var x = Std.parseFloat(TOKEN.matched(1));
				if (unit == null) kinds.push("n") else if (unit == "%") kinds.push("p") else {
					kinds.push("a");
					x = switch unit {
						case "rad": x * 180 / Math.PI;
						case "grad": x * 0.9;
						case "turn": x * 360;
						case _: x;
					}
				}
				values.push(x);
				// (a number runs into the next token only through a separator: "1. 0" is two)
				var after = TOKEN.matchedRight();
				if (after.length > 0 && !StringTools.isSpace(after, 0) && after.charAt(0) != "," && after.charAt(0) != "/") return null;
			} else if (TOKEN.matched(3) != null) {
				kinds.push("x");
				values.push(0);
			} else if (TOKEN.matched(4) != null) {
				kinds.push("c");
				values.push(0);
			} else {
				kinds.push("s");
				values.push(0);
			}
			t = TOKEN.matchedRight();
		}
		var legacy = kinds.indexOf("c") >= 0;
		var parts:Array<Int> = [], alpha = 1.0;
		if (legacy) {
			// (value, comma, value, comma, value[, comma, alpha]: no none, no slash)
			if (kinds.length != 5 && kinds.length != 7) return null;
			for (i in 0...kinds.length)
				if ((i % 2 == 1) != (kinds[i] == "c")) return null;
			if (kinds.indexOf("x") >= 0 || kinds.indexOf("s") >= 0) return null;
			if (kinds.length == 7) {
				if (kinds[6] != "n" && kinds[6] != "p") return null;
				alpha = kinds[6] == "p" ? values[6] / 100 : values[6];
			}
			parts = [0, 2, 4];
		} else {
			// (value value value[ / alpha])
			if (kinds.length != 3 && kinds.length != 5) return null;
			for (i in 0...3)
				if (kinds[i] == "c" || kinds[i] == "s") return null;
			if (kinds.length == 5) {
				if (kinds[3] != "s" || (kinds[4] != "n" && kinds[4] != "p" && kinds[4] != "x")) return null;
				alpha = kinds[4] == "p" ? values[4] / 100 : kinds[4] == "x" ? 0 : values[4];
			}
			parts = [0, 1, 2];
		}
		var a = Std.int(Math.round(clamp(alpha, 0, 1) * 255));
		var k0 = kinds[parts[0]], k1 = kinds[parts[1]], k2 = kinds[parts[2]];
		var v0 = values[parts[0]], v1 = values[parts[1]], v2 = values[parts[2]];
		if (name == "rgb" || name == "rgba") {
			for (k in [k0, k1, k2])
				if (k == "a") return null;
			// (the legacy form: all numbers or all percentages)
			if (legacy && !((k0 == "n" && k1 == "n" && k2 == "n") || (k0 == "p" && k1 == "p" && k2 == "p"))) return null;
			inline function ch(k:String, x:Float):Int
				return Std.int(Math.round(clamp(k == "p" ? x * 2.55 : k == "x" ? 0 : x, 0, 255)));
			return (a << 24) | (ch(k0, v0) << 16) | (ch(k1, v1) << 8) | ch(k2, v2);
		}
		// hsl: a hue (a number or an angle), then saturation and lightness (percentages; numbers too in the space form)
		if (k0 == "p") return null;
		if (legacy && (k1 != "p" || k2 != "p")) return null;
		if (k1 == "a" || k2 == "a") return null;
		var h = k0 == "x" ? 0 : v0, sat = k1 == "x" ? 0 : v1 / 100, l = k2 == "x" ? 0 : v2 / 100;
		h = ((h % 360) + 360) % 360 / 30;
		sat = clamp(sat, 0, 1);
		l = clamp(l, 0, 1);
		inline function f(n:Float):Float {
			var k = (n + h) % 12, q = sat * Math.min(l, 1 - l);
			return l - q * Math.max(-1, Math.min(Math.min(k - 3, 9 - k), 1));
		}
		inline function byte(x:Float):Int
			return Std.int(Math.round(clamp(x, 0, 1) * 255));
		return (a << 24) | (byte(f(0)) << 16) | (byte(f(8)) << 8) | byte(f(4));
	}

	static inline function clamp(x:Float, lo:Float, hi:Float):Float
		return x < lo ? lo : x > hi ? hi : x;

	public static function serialize(c:Int):String {
		var a = (c >>> 24) & 255, r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
		if (a == 255) return "#" + StringTools.hex(r, 2).toLowerCase() + StringTools.hex(g, 2).toLowerCase() + StringTools.hex(b, 2).toLowerCase();
		// (the alpha as the browser prints it: the shortest decimal that rounds back to the byte)
		var alpha = "0";
		if (a > 0) {
			var two = Math.round(a / 255 * 100) / 100;
			alpha = Std.int(Math.round(two * 255)) == a ? Std.string(two) : Std.string(Math.round(a / 255 * 1000) / 1000);
		}
		return 'rgba($r, $g, $b, $alpha)';
	}
}
