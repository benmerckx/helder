// JavaScript's toFixed for the Haxe versions of bench/'s programs (their
// output the same as the TypeScript's)
class Fixed {
	public static function of(v:Float, digits:Int):String {
		var m = Math.pow(10, digits);
		var n = Math.ffloor(Math.abs(v) * m + 0.5);
		var whole = Math.ffloor(n / m), frac = Std.int(n - whole * m);
		var f = Std.string(frac);
		while (f.length < digits) f = "0" + f;
		var w = Std.string(whole);
		if (StringTools.endsWith(w, ".0")) w = w.substr(0, w.length - 2);
		return (v < 0 && n > 0 ? "-" : "") + w + (digits > 0 ? "." + f : "");
	}
}
