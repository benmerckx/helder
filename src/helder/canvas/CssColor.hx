package helder.canvas;

// A CSS colour as 0xAARRGGBB (straight alpha), null when it is not one:
// "#rgb", "#rgba", "#rrggbb", "#rrggbbaa" (the # may be left out), rgb()
// and rgba() (numbers or percentages, commas or spaces, an alpha after a
// slash), hsl() and hsla(), oklch() and oklab() (to sRGB, clipped), the
// 148 names (as Chromium has them), transparent. helder.ui's Color (its
// tokens besides), Svg's paints and the DOM facade's styles read them so.
class CssColor {
	public static function parse(s:String):Null<Int> {
		// (#rgb, #rgba, #rrggbb and #rrggbbaa as written, digit by digit: no strings made)
		var n = s.length;
		if ((n == 4 || n == 5 || n == 7 || n == 9) && StringTools.fastCodeAt(s, 0) == "#".code) {
			var x = 0, ok = true;
			for (i in 1...n) {
				var d = hexDigit(StringTools.fastCodeAt(s, i));
				if (d < 0) {
					ok = false;
					break;
				}
				x = n <= 5 ? (x << 8) | (d * 17) : (x << 4) | d;
			}
			if (ok) return n == 4 || n == 7 ? (0xFF000000 | x) : ((x & 0xFF) << 24) | (x >>> 8);
		}
		var v = StringTools.trim(s).toLowerCase();
		if (v == "transparent") return 0;
		var hex = v.charAt(0) == "#" ? v.substr(1) : v;
		if ((hex.length == 3 || hex.length == 4 || hex.length == 6 || hex.length == 8) && isHex(hex)) {
			if (hex.length <= 4) {
				var b = new StringBuf();
				for (k in 0...hex.length) {
					b.add(hex.charAt(k));
					b.add(hex.charAt(k));
				}
				hex = b.toString();
			}
			var n = Std.parseInt("0x" + hex);
			return hex.length == 6 ? 0xFF000000 | n : ((n & 0xFF) << 24) | (n >>> 8);
		}
		var open = v.indexOf("("), close = v.lastIndexOf(")");
		if (open > 0 && close > open) {
			var fn = StringTools.trim(v.substr(0, open));
			var parts = args(v.substring(open + 1, close));
			if (parts.length < 3) return null;
			var alpha = 1.0;
			if (parts.length > 3) alpha = StringTools.endsWith(parts[3], "%") ? Std.parseFloat(parts[3]) / 100 : Std.parseFloat(parts[3]);
			if (Math.isNaN(alpha)) return null;
			var a = Std.int(Math.round(clamp(alpha) * 255));
			if (fn == "rgb" || fn == "rgba") {
				var ch = [for (k in 0...3) StringTools.endsWith(parts[k], "%") ? Std.parseFloat(parts[k]) * 2.55 : Std.parseFloat(parts[k])];
				for (x in ch)
					if (Math.isNaN(x)) return null;
				inline function byte(x:Float):Int
					return Std.int(Math.max(0, Math.min(255, Math.round(x))));
				return (a << 24) | (byte(ch[0]) << 16) | (byte(ch[1]) << 8) | byte(ch[2]);
			}
			if (fn == "hsl" || fn == "hsla") {
				var h = Std.parseFloat(StringTools.replace(parts[0], "deg", "")), sat = Std.parseFloat(parts[1]) / 100, l = Std.parseFloat(parts[2]) / 100;
				if (Math.isNaN(h + sat + l)) return null;
				h = ((h % 360) + 360) % 360 / 30;
				sat = clamp(sat);
				l = clamp(l);
				// (CSS Color 4's hsl to rgb)
				function f(n:Float):Float {
					var k = (n + h) % 12, q = sat * Math.min(l, 1 - l);
					return l - q * Math.max(-1, Math.min(Math.min(k - 3, 9 - k), 1));
				}
				inline function byte(x:Float):Int
					return Std.int(Math.round(clamp(x) * 255));
				return (a << 24) | (byte(f(0)) << 16) | (byte(f(8)) << 8) | byte(f(4));
			}
			if (fn == "oklch" || fn == "oklab") {
				// (L a number or a percentage; oklch's C and h, oklab's a and b, percentages of 0.4)
				inline function num(p:String, percent:Float):Float
					return StringTools.endsWith(p, "%") ? Std.parseFloat(p) / 100 * percent : Std.parseFloat(StringTools.replace(p, "deg", ""));
				var l = num(parts[0], 1), x = num(parts[1], 0.4), y = num(parts[2], fn == "oklch" ? 1 : 0.4);
				if (Math.isNaN(l + x + y)) return null;
				var oa = x, ob = y;
				if (fn == "oklch") {
					var h = y * Math.PI / 180;
					oa = x * Math.cos(h);
					ob = x * Math.sin(h);
				}
				// (Oklab to linear sRGB, then sRGB's curve)
				var l_ = l + 0.3963377774 * oa + 0.2158037573 * ob, m_ = l - 0.1055613458 * oa - 0.0638541728 * ob,
					s_ = l - 0.0894841775 * oa - 1.2914855480 * ob;
				var lc = l_ * l_ * l_, mc = m_ * m_ * m_, sc = s_ * s_ * s_;
				var rl = 4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc, gl = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc,
					bl = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc;
				inline function encode(c:Float):Int {
					c = clamp(c);
					return Std.int(Math.round((c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055) * 255));
				}
				return (a << 24) | (encode(rl) << 16) | (encode(gl) << 8) | encode(bl);
			}
			return null;
		}
		var n = names().get(v);
		return n == null ? null : 0xFF000000 | n;
	}

	static inline function clamp(f:Float):Float
		return f < 0 ? 0 : f > 1 ? 1 : f;

	// (a hex digit's value, either case; -1 for anything else)
	static inline function hexDigit(c:Int):Int {
		var l = c | 32;
		return c >= "0".code && c <= "9".code ? c - "0".code : l >= "a".code && l <= "f".code ? l - "a".code + 10 : -1;
	}

	// (a function's arguments: the parts between spaces, commas and slashes)
	static function args(s:String):Array<String> {
		var out = [], start = 0;
		for (i in 0...s.length + 1)
			if (i == s.length || StringTools.fastCodeAt(s, i) == ",".code || StringTools.fastCodeAt(s, i) == "/".code || StringTools.isSpace(s, i)) {
				if (i > start) out.push(s.substring(start, i));
				start = i + 1;
			}
		return out;
	}

	// (hex digits only; lower case)
	static function isHex(s:String):Bool {
		for (i in 0...s.length) {
			var c = StringTools.fastCodeAt(s, i);
			if (!(c >= "0".code && c <= "9".code || c >= "a".code && c <= "f".code)) return false;
		}
		return true;
	}

	static var table:Null<Map<String, Int>>;

	// (made when first asked: an svg parsed by a static initializer runs before this class's)
	static function names():Map<String, Int> {
		if (table == null) table = make();
		return table;
	}

	static function make():Map<String, Int>
		return [
			"aliceblue" => 0xF0F8FF,
			"antiquewhite" => 0xFAEBD7,
			"aqua" => 0x00FFFF,
			"aquamarine" => 0x7FFFD4,
			"azure" => 0xF0FFFF,
			"beige" => 0xF5F5DC,
			"bisque" => 0xFFE4C4,
			"black" => 0x000000,
			"blanchedalmond" => 0xFFEBCD,
			"blue" => 0x0000FF,
			"blueviolet" => 0x8A2BE2,
			"brown" => 0xA52A2A,
			"burlywood" => 0xDEB887,
			"cadetblue" => 0x5F9EA0,
			"chartreuse" => 0x7FFF00,
			"chocolate" => 0xD2691E,
			"coral" => 0xFF7F50,
			"cornflowerblue" => 0x6495ED,
			"cornsilk" => 0xFFF8DC,
			"crimson" => 0xDC143C,
			"cyan" => 0x00FFFF,
			"darkblue" => 0x00008B,
			"darkcyan" => 0x008B8B,
			"darkgoldenrod" => 0xB8860B,
			"darkgray" => 0xA9A9A9,
			"darkgreen" => 0x006400,
			"darkgrey" => 0xA9A9A9,
			"darkkhaki" => 0xBDB76B,
			"darkmagenta" => 0x8B008B,
			"darkolivegreen" => 0x556B2F,
			"darkorange" => 0xFF8C00,
			"darkorchid" => 0x9932CC,
			"darkred" => 0x8B0000,
			"darksalmon" => 0xE9967A,
			"darkseagreen" => 0x8FBC8F,
			"darkslateblue" => 0x483D8B,
			"darkslategray" => 0x2F4F4F,
			"darkslategrey" => 0x2F4F4F,
			"darkturquoise" => 0x00CED1,
			"darkviolet" => 0x9400D3,
			"deeppink" => 0xFF1493,
			"deepskyblue" => 0x00BFFF,
			"dimgray" => 0x696969,
			"dimgrey" => 0x696969,
			"dodgerblue" => 0x1E90FF,
			"firebrick" => 0xB22222,
			"floralwhite" => 0xFFFAF0,
			"forestgreen" => 0x228B22,
			"fuchsia" => 0xFF00FF,
			"gainsboro" => 0xDCDCDC,
			"ghostwhite" => 0xF8F8FF,
			"gold" => 0xFFD700,
			"goldenrod" => 0xDAA520,
			"gray" => 0x808080,
			"green" => 0x008000,
			"greenyellow" => 0xADFF2F,
			"grey" => 0x808080,
			"honeydew" => 0xF0FFF0,
			"hotpink" => 0xFF69B4,
			"indianred" => 0xCD5C5C,
			"indigo" => 0x4B0082,
			"ivory" => 0xFFFFF0,
			"khaki" => 0xF0E68C,
			"lavender" => 0xE6E6FA,
			"lavenderblush" => 0xFFF0F5,
			"lawngreen" => 0x7CFC00,
			"lemonchiffon" => 0xFFFACD,
			"lightblue" => 0xADD8E6,
			"lightcoral" => 0xF08080,
			"lightcyan" => 0xE0FFFF,
			"lightgoldenrodyellow" => 0xFAFAD2,
			"lightgray" => 0xD3D3D3,
			"lightgreen" => 0x90EE90,
			"lightgrey" => 0xD3D3D3,
			"lightpink" => 0xFFB6C1,
			"lightsalmon" => 0xFFA07A,
			"lightseagreen" => 0x20B2AA,
			"lightskyblue" => 0x87CEFA,
			"lightslategray" => 0x778899,
			"lightslategrey" => 0x778899,
			"lightsteelblue" => 0xB0C4DE,
			"lightyellow" => 0xFFFFE0,
			"lime" => 0x00FF00,
			"limegreen" => 0x32CD32,
			"linen" => 0xFAF0E6,
			"magenta" => 0xFF00FF,
			"maroon" => 0x800000,
			"mediumaquamarine" => 0x66CDAA,
			"mediumblue" => 0x0000CD,
			"mediumorchid" => 0xBA55D3,
			"mediumpurple" => 0x9370DB,
			"mediumseagreen" => 0x3CB371,
			"mediumslateblue" => 0x7B68EE,
			"mediumspringgreen" => 0x00FA9A,
			"mediumturquoise" => 0x48D1CC,
			"mediumvioletred" => 0xC71585,
			"midnightblue" => 0x191970,
			"mintcream" => 0xF5FFFA,
			"mistyrose" => 0xFFE4E1,
			"moccasin" => 0xFFE4B5,
			"navajowhite" => 0xFFDEAD,
			"navy" => 0x000080,
			"oldlace" => 0xFDF5E6,
			"olive" => 0x808000,
			"olivedrab" => 0x6B8E23,
			"orange" => 0xFFA500,
			"orangered" => 0xFF4500,
			"orchid" => 0xDA70D6,
			"palegoldenrod" => 0xEEE8AA,
			"palegreen" => 0x98FB98,
			"paleturquoise" => 0xAFEEEE,
			"palevioletred" => 0xDB7093,
			"papayawhip" => 0xFFEFD5,
			"peachpuff" => 0xFFDAB9,
			"peru" => 0xCD853F,
			"pink" => 0xFFC0CB,
			"plum" => 0xDDA0DD,
			"powderblue" => 0xB0E0E6,
			"purple" => 0x800080,
			"rebeccapurple" => 0x663399,
			"red" => 0xFF0000,
			"rosybrown" => 0xBC8F8F,
			"royalblue" => 0x4169E1,
			"saddlebrown" => 0x8B4513,
			"salmon" => 0xFA8072,
			"sandybrown" => 0xF4A460,
			"seagreen" => 0x2E8B57,
			"seashell" => 0xFFF5EE,
			"sienna" => 0xA0522D,
			"silver" => 0xC0C0C0,
			"skyblue" => 0x87CEEB,
			"slateblue" => 0x6A5ACD,
			"slategray" => 0x708090,
			"slategrey" => 0x708090,
			"snow" => 0xFFFAFA,
			"springgreen" => 0x00FF7F,
			"steelblue" => 0x4682B4,
			"tan" => 0xD2B48C,
			"teal" => 0x008080,
			"thistle" => 0xD8BFD8,
			"tomato" => 0xFF6347,
			"turquoise" => 0x40E0D0,
			"violet" => 0xEE82EE,
			"wheat" => 0xF5DEB3,
			"white" => 0xFFFFFF,
			"whitesmoke" => 0xF5F5F5,
			"yellow" => 0xFFFF00,
			"yellowgreen" => 0x9ACD32
		];
}
