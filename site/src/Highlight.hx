using StringTools;

// Code blocks highlighted at build time, as spans with classes (style.css:
// .k keyword, .s string, .c comment, .n number, .m metadata, .t type):
// Haxe (and what looks like it: JavaScript, hxml's -D lines), shell and
// hxml comments. Anything else is escaped text.
class Highlight {
	static final KEYWORDS = [
		for (k in "abstract break case cast catch class continue default do dynamic else enum extends extern false final for function if implements import in inline interface macro new null operator overload override package private public return static super switch this throw true try typedef untyped using var while const let async await export from yield"
			.split(" ")) k => true
	];

	// a <pre><code> block
	public static function block(code:String, lang:String):String {
		var l = lang == null ? "" : lang.toLowerCase();
		var body = switch l {
			case "haxe" | "hx" | "js" | "javascript" | "mjs" | "ts": haxe(code);
			case "sh" | "shell" | "bash" | "console" | "hxml" | "make" | "makefile": hashComments(code);
			case _: Esc.html(code);
		}
		var cls = l == "" ? "" : ' class="lang-$l"';
		return '<pre class="code"><code$cls>$body</code></pre>';
	}

	static function span(cls:String, text:String):String
		return '<span class="$cls">${Esc.html(text)}</span>';

	static function isIdent(c:Int, first:Bool):Bool
		return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c == "_".code || (!first && c >= "0".code && c <= "9".code);

	public static function haxe(code:String):String {
		var b = new StringBuf();
		var k = 0, n = code.length;
		while (k < n) {
			var c = code.charCodeAt(k);
			if (c == "/".code && code.charCodeAt(k + 1) == "/".code) {
				var e = code.indexOf("\n", k);
				if (e < 0) e = n;
				b.add(span("c", code.substring(k, e)));
				k = e;
			} else if (c == "/".code && code.charCodeAt(k + 1) == "*".code) {
				var e = code.indexOf("*/", k + 2);
				e = e < 0 ? n : e + 2;
				b.add(span("c", code.substring(k, e)));
				k = e;
			} else if (c == '"'.code || c == "'".code) {
				var e = k + 1;
				while (e < n && code.charCodeAt(e) != c) {
					if (code.charCodeAt(e) == "\\".code) e++;
					if (code.charCodeAt(e) == "\n".code && c == '"'.code) break;
					e++;
				}
				e = Std.int(Math.min(e + 1, n));
				b.add(span("s", code.substring(k, e)));
				k = e;
			} else if (c >= "0".code && c <= "9".code) {
				var e = k + 1;
				while (e < n && (isIdent(code.charCodeAt(e), false) || code.charCodeAt(e) == ".".code && code.charCodeAt(e + 1) != ".".code))
					e++;
				b.add(span("n", code.substring(k, e)));
				k = e;
			} else if (c == "@".code) {
				var e = k + 1;
				if (code.charCodeAt(e) == ":".code) e++;
				while (e < n && (isIdent(code.charCodeAt(e), false) || code.charCodeAt(e) == ".".code))
					e++;
				b.add(span("m", code.substring(k, e)));
				k = e;
			} else if (isIdent(c, true)) {
				var e = k + 1;
				while (e < n && isIdent(code.charCodeAt(e), false))
					e++;
				var w = code.substring(k, e);
				if (KEYWORDS.exists(w)) b.add(span("k", w));
				else if (c >= "A".code && c <= "Z".code) b.add(span("t", w));
				else b.add(w);
				k = e;
			} else {
				b.add(Esc.html(code.charAt(k)));
				k++;
			}
		}
		return b.toString();
	}

	static function hashComments(code:String):String {
		return [
			for (line in code.split("\n")) {
				var h = line.indexOf("#");
				// (a # that starts a comment: at the start or after a space)
				while (h > 0 && line.charAt(h - 1) != " ")
					h = line.indexOf("#", h + 1);
				h < 0 ? Esc.html(line) : Esc.html(line.substr(0, h)) + span("c", line.substr(h));
			}
		].join("\n");
	}
}
