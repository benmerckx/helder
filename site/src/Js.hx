// JavaScript operators and methods the Haxe types do not expose, with their
// JavaScript semantics (truthiness, number formatting), and the DOM helper
// the pages share.
class Js {
	/** `a || b` */
	public static inline function or<T>(a:T, b:T):T {
		return js.Syntax.code("({0} || {1})", a, b);
	}

	/** `!!x` */
	public static inline function truthy(x:Dynamic):Bool {
		return js.Syntax.code("!!{0}", x);
	}

	/** `x.toFixed(digits)` */
	public static inline function fixed(x:Float, digits:Int):String {
		return js.Syntax.code("{0}.toFixed({1})", x, digits);
	}

	/** `String(x)` */
	public static inline function str(x:Dynamic):String {
		return js.Syntax.code("String({0})", x);
	}

	/** `x.toLocaleString()` */
	public static inline function locale(x:Float):String {
		return js.Syntax.code("{0}.toLocaleString()", x);
	}

	/** `Math.min(a, ...xs)` */
	public static function min(a:Float, xs:Array<Float>):Float {
		for (x in xs) a = Math.min(a, x);
		return a;
	}

	/** `Math.max(a, ...xs)` */
	public static function max(a:Float, xs:Array<Float>):Float {
		for (x in xs) a = Math.max(a, x);
		return a;
	}

	/** an element with an optional class and text */
	public static function el(tag:String, ?cls:String, ?text:String):js.html.Element {
		final e = js.Browser.document.createElement(tag);
		if (truthy(cls)) e.className = cls;
		if (text != null) e.textContent = text;
		return e;
	}
}
