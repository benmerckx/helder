package hxmc.ui;

// A colour as 0xAARRGGBB (straight alpha). From an Int literal written
// 0xRRGGBB it is opaque only through rgb(): `Color.rgb(0x3366ff)`;
// `Color.rgba(0x3366ff, 0.5)`; TRANSPARENT is 0.
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

	// this colour with its alpha multiplied by f
	public inline function fade(f:Float):Color
		return (Std.int(a * clamp(f) + 0.5) << 24) | (this & 0xFFFFFF);

	// the colour a fraction t of the way from a to b (each channel)
	public static function mix(a:Color, b:Color, t:Float):Color {
		inline function ch(x:Int, y:Int):Int
			return Std.int(x + (y - x) * t + 0.5);
		return (ch(a.a, b.a) << 24) | (ch(a.r, b.r) << 16) | (ch(a.g, b.g) << 8) | ch(a.b, b.b);
	}

	// "#rrggbbaa"
	public function toHex():String
		return "#" + StringTools.hex(r, 2) + StringTools.hex(g, 2) + StringTools.hex(b, 2) + StringTools.hex(a, 2);

	// a CSS-like hex string: "#rgb", "#rrggbb", "#rrggbbaa"
	public static function parse(s:String):Color {
		if (s.charAt(0) == "#") s = s.substr(1);
		if (s.length == 3) s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2);
		var v = Std.parseInt("0x" + s);
		if (v == null || (s.length != 6 && s.length != 8)) throw "Color.parse: " + s;
		return s.length == 6 ? rgb(v) : ((v & 0xFF) << 24) | (v >>> 8);
	}

	static inline function clamp(f:Float):Float
		return f < 0 ? 0 : f > 1 ? 1 : f;
}
