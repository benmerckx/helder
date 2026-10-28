package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Lib.*;

class JsRawJson extends JsObject {
	public var raw:String;
	public function new(text:String) {
		super(null);
		raw = text;
		setOwn("rawJSON", text, Attr.READONLY | Attr.LOCKED);
		extensible = false;
	}
}

@:access(helder.typescript.js.Json)
class RawJson {
	public static function setup(target:JsObject):Void {
		target.setOwn("rawJSON", Builtins.nativeFunction("rawJSON", 1, (_, a, _) -> {
			var text = Seed.text(arg(a, 0));
			var value = new Json(text).document();
			if (isObject(value) || text.length == 0 || whitespace(text.charCodeAt(0)) || whitespace(text.charCodeAt(text.length - 1))) return error("SyntaxError", "Invalid raw JSON text");
			return new JsRawJson(text);
		}), Attr.HIDDEN);
		target.setOwn("isRawJSON", Builtins.nativeFunction("isRawJSON", 1, (_, a, _) -> Std.isOfType(arg(a, 0), JsRawJson)), Attr.HIDDEN);
	}

	static function whitespace(c:Int):Bool return c == 32 || c == 9 || c == 10 || c == 13;
}
