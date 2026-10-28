package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Lib.*;

@:access(helder.typescript.js.Builtins)
class RegexEscapes {
	public static function setup():Void {
		var ctor:JsObject = Builtins.globals.get("RegExp");
		Builtins.getter(ctor, "\x00@@species", t -> t);
		Builtins.method(ctor, "escape", 1, (_, a, _) -> escape(arg(a, 0)));
	}

	public static function escape(value:Dynamic):String {
		if (!Std.isOfType(value, String)) return error("TypeError", "RegExp.escape requires a string");
		var s:String = value, out = new StringBuf(), i = 0;
		while (i < s.length) {
			var c = s.charCodeAt(i), ch = s.charAt(i);
			if (i == 0 && (c >= 48 && c <= 57 || c >= 65 && c <= 90 || c >= 97 && c <= 122)) out.add("\\x" + StringTools.hex(c, 2).toLowerCase());
			else if ("^$\\.*+?()[]{}|/".indexOf(ch) >= 0) out.add("\\" + ch);
			else if (c == 9 || c == 10 || c == 11 || c == 12 || c == 13) out.add("\\" + (c == 9 ? "t" : c == 10 ? "n" : c == 11 ? "v" : c == 12 ? "f" : "r"));
			else if (",-=<>#&!%:;@~'`\"".indexOf(ch) >= 0 || c == 32) out.add("\\x" + StringTools.hex(c, 2).toLowerCase());
			else if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length && s.charCodeAt(i + 1) >= 0xdc00 && s.charCodeAt(i + 1) <= 0xdfff) {
				out.add(s.substr(i, 2));
				i++;
			}
			else if (Seed.whitespace(c) || c >= 0xd800 && c <= 0xdfff) out.add((c <= 255 ? "\\x" : "\\u") + StringTools.hex(c, c <= 255 ? 2 : 4).toLowerCase());
			else out.add(ch);
			i++;
		}
		return out.toString();
	}
}
