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

	// as parse, null when it is not one
	public static function tryParse(s:String):Null<Color> {
		var c:Null<Color> = helder.canvas.CssColor.parse(s);
		if (c != null) return c;
		var v = StringTools.trim(s).toLowerCase();
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
		return null;
	}

	static inline function clamp(f:Float):Float
		return f < 0 ? 0 : f > 1 ? 1 : f;
}
