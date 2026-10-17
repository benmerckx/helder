import js.Browser.document;
import js.html.Element;

// What the page scripts share: building elements and formatting numbers.
class Ui {
	public static function el(tag:String, cls = "", ?text:String):Element {
		final e = document.createElement(tag);
		if (cls != "") e.className = cls;
		if (text != null) e.textContent = text;
		return e;
	}

	/** JavaScript's `Number.prototype.toFixed` */
	public static inline function fixed(x:Float, digits:Int):String {
		return js.Syntax.code("{0}.toFixed({1})", x, digits);
	}

	public static function error(e:Dynamic):String {
		return e != null && e.message != null ? e.message : Std.string(e);
	}
}
