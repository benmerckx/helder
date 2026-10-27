package helder.ui;

// A length that names a sheet's token, as Color.token names a colour:
// Length.token("radius", -4) is CSS's calc(var(--radius) - 4px), resolved
// with the sheet's lengths (StyleSheet.lengths) when a rule giving it is
// applied (a name the sheet lacks: 0, plus the offset), so that a sheet's
// --radius changes every rounded corner. Encoded in the Float it stands
// for, far below any length (Length.isToken): a property it reaches
// unresolved is that number.
class Length {
	static inline var BASE = 2e14;
	static inline var NAME = 1e8;
	static inline var STEP = 16.0;
	static inline var BIAS = 1e6;
	static final names:Array<String> = [];
	static final index = new Map<String, Int>();

	// a reference to the length name plus offset pixels (to a sixteenth)
	public static function token(name:String, offset = 0.0):Float {
		var k = index.get(name);
		if (k == null) {
			k = names.length;
			names.push(name);
			index.set(name, k);
		}
		return -(BASE + k * NAME + Math.fround((offset + BIAS) * STEP));
	}

	public static inline function isToken(v:Float):Bool
		return v <= -BASE;

	public static function tokenName(v:Float):String
		return names[Std.int(Math.ffloor((-v - BASE) / NAME))];

	public static function tokenOffset(v:Float):Float {
		var u = -v - BASE;
		return (u - Math.ffloor(u / NAME) * NAME) / STEP - BIAS;
	}

	// v resolved with lengths (not a token: itself)
	public static function resolve(v:Float, lengths:Null<Map<String, Float>>):Float {
		if (!isToken(v)) return v;
		var base = lengths == null ? null : lengths.get(tokenName(v));
		return (base == null ? 0 : base) + tokenOffset(v);
	}
}
