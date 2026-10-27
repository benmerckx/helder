package helder.ui;

// A colour as 0xAARRGGBB (straight alpha). From an Int literal written
// 0xRRGGBB it is opaque only through rgb(): `Color.rgb(0x3366ff)`;
// `Color.rgba(0x3366ff, 0.5)`; TRANSPARENT is 0. A token reference
// (Color.token, "var(--primary)", "var(--ring)/50") stands for a style
// sheet's colour of that name (StyleSheet), resolved when a rule using it
// is applied: drawn as it is, it is transparent (its alpha is 0; its other
// bytes name the token and its alpha, so a transparent colour with any
// other byte set is one); "currentColor" is one, the text's colour where
// it is applied, and so are the system colours "Canvas" and "CanvasText"
// (a sheet's colours of those names, else the browser's, light or dark).
abstract Color(Int) from Int to Int {
	public static inline var TRANSPARENT:Color = 0;
	public static inline var BLACK:Color = 0xFF000000;
	public static inline var WHITE:Color = 0xFFFFFFFF;

	public static inline function rgb(rgb:Int):Color
		return 0xFF000000 | (rgb & 0xFFFFFF);

	public static inline function rgba(rgb:Int, alpha:Float):Color
		return (Std.int(clamp(alpha) * 255 + 0.5) << 24) | (rgb & 0xFFFFFF);

	public static inline function fromFloats(r:Float, g:Float, b:Float, a = 1.0):Color
		return (Std.int(clamp(a) * 255 + 0.5) << 24) | (Std.int(clamp(r) * 255 + 0.5) << 16) | (Std.int(clamp(g) * 255 + 0.5) << 8)
			| Std.int(clamp(b) * 255 + 0.5);

	public var a(get, never):Int;
	public var r(get, never):Int;
	public var g(get, never):Int;
	public var b(get, never):Int;

	inline function get_a()
		return (this >>> 24) & 0xFF;

	inline function get_r()
		return (this >> 16) & 0xFF;

	inline function get_g()
		return (this >> 8) & 0xFF;

	inline function get_b()
		return this & 0xFF;

	// a reference to a style sheet's colour (its name without the dashes:
	// "primary"), its alpha a share of it (Tailwind's /50: 0.5)
	public static function token(name:String, alpha = 1.0):Color {
		var k = tokenIndex.get(name);
		if (k == null) {
			k = tokenNames.length;
			tokenNames.push(name);
			tokenIndex.set(name, k);
		}
		return ((Std.int(clamp(alpha) * 100 + 0.5) + 1) << 16) | (k + 1);
	}

	static final tokenNames:Array<String> = [];
	static final tokenIndex = new Map<String, Int>();

	// whether this is a token reference (Color.token)
	public var isToken(get, never):Bool;

	inline function get_isToken():Bool
		return a == 0 && r >= 1 && r <= 101 && (this & 0xFFFF) != 0;

	// a token reference's name and alpha
	public function tokenName():String
		return tokenNames[(this & 0xFFFF) - 1];

	public inline function tokenAlpha():Float
		return (r - 1) / 100;

	// this colour with its alpha multiplied by f
	public inline function fade(f:Float):Color
		return (Std.int(a * clamp(f) + 0.5) << 24) | (this & 0xFFFFFF);

	// the colour a fraction t of the way from a to b (each channel)
	public static function mix(a:Color, b:Color, t:Float):Color {
		inline function ch(x:Int, y:Int):Int
			return Std.int(x + (y - x) * t + 0.5);
		return (ch(a.a, b.a) << 24) | (ch(a.r, b.r) << 16) | (ch(a.g, b.g) << 8) | ch(a.b, b.b);
	}

	// the colour a fraction t of the way from a to b with their alphas
	// premultiplied, as CSS interpolates (transparent to red: red fading in,
	// not through black)
	public static function between(a:Color, b:Color, t:Float):Color {
		var aa = a.a / 255, ba = b.a / 255, alpha = aa + (ba - aa) * t;
		if (alpha <= 0) return TRANSPARENT;
		inline function ch(x:Int, y:Int):Int {
			var v = (x * aa + (y * ba - x * aa) * t) / alpha;
			return Std.int(Math.max(0, Math.min(255, v + 0.5)));
		}
		return (Std.int(alpha * 255 + 0.5) << 24) | (ch(a.r, b.r) << 16) | (ch(a.g, b.g) << 8) | ch(a.b, b.b);
	}

	// "#RRGGBBAA" (built a character at a time: animated colours make one a frame)
	public function toHex():String {
		inline function digit(d:Int):Int
			return d < 10 ? "0".code + d : "A".code - 10 + d;
		var s = new StringBuf();
		s.addChar("#".code);
		inline function byte(v:Int) {
			s.addChar(digit(v >> 4));
			s.addChar(digit(v & 15));
		}
		byte(r);
		byte(g);
		byte(b);
		byte(a);
		return s.toString();
	}

	// a CSS colour: "#rgb", "#rgba", "#rrggbb", "#rrggbbaa" (the # may be
	// left out), rgb() and rgba() (numbers or percentages, commas or
	// spaces, an alpha after a slash), hsl() and hsla(), oklch() and
	// oklab() (to sRGB, clipped), the 148 names, transparent; a token
	// reference, "var(--primary)" or "var(--ring)/50", "currentColor",
	// "Canvas" or "CanvasText" (each with an alpha after a slash); anything else throws
	public static function parse(s:String):Color {
		var c = tryParse(s);
		if (c == null) throw "Color.parse: " + s;
		return c;
	}

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

	// as parse, null when it is not one
	public static function tryParse(s:String):Null<Color> {
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
			if (ok) return n == 4 || n == 7 ? rgb(x) : ((x & 0xFF) << 24) | (x >>> 8);
		}
		var v = StringTools.trim(s).toLowerCase();
		if (v == "transparent") return TRANSPARENT;
		// (a token: var(--name), or the text's colour where a rule is applied, currentColor, or a system colour; an alpha percentage after a slash)
		var named = StringTools.startsWith(v, "currentcolor") ? "currentcolor" : StringTools.startsWith(v, "canvastext") ? "canvastext" : StringTools.startsWith(v,
			"canvas") ? "canvas" : null;
		if (named != null || StringTools.startsWith(v, "var(--")) {
			var close = named != null ? named.length - 1 : v.indexOf(")");
			if (close < 0) return null;
			var name = named ?? v.substring(6, close), rest = StringTools.trim(v.substr(close + 1)), alpha = 1.0;
			if (rest != "") {
				if (rest.charAt(0) != "/") return null;
				var p = StringTools.trim(StringTools.replace(rest.substr(1), "%", ""));
				alpha = Std.parseFloat(p) / 100;
				if (Math.isNaN(alpha)) return null;
			}
			return token(name, alpha);
		}
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
			return hex.length == 6 ? rgb(n) : ((n & 0xFF) << 24) | (n >>> 8);
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
		var n = CssColors.names().get(v);
		return n == null ? null : rgb(n);
	}

	static inline function clamp(f:Float):Float
		return f < 0 ? 0 : f > 1 ? 1 : f;
}
