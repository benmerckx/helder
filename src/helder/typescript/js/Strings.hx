package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Symbols.JsSymbol;
import helder.typescript.js.Lib.*;
import helder.typescript.js.Builtins.*;
import helder.typescript.js.Objects.*;
import helder.typescript.js.Arrays.*;
import helder.typescript.js.Collections.*;
import helder.typescript.js.Globals.*;

// String's built-ins: String and its prototype's methods, localeCompare's collation.
@:access(helder.typescript.js.Builtins)
@:access(helder.typescript.js.Objects)
@:access(helder.typescript.js.Arrays)
@:access(helder.typescript.js.Collections)
@:access(helder.typescript.js.Globals)
class Strings {
	// String
	static function thisString(t:Dynamic):String {
		if (t == null || t == undef()) error("TypeError", "String.prototype method called on null or undefined");
		if (Std.isOfType(t, String)) return t;
		return Seed.text(isObject(t) ? toPrimitive(t, "string") : t);
	}

	static function setupString():Void {
		var p = StringProto;
		constant(p, "length", 0);
		p.setOwn("\x00@primitive", "", Attr.HIDDEN);
		var c = constructor("String", 1, p, (_, a, nt) -> {
			var v = a.length == 0 ? "" : Std.isOfType(a[0], Symbols.JsSymbol) && nt == undef() ? Symbols.text(a[0]) : Seed.text(isObject(a[0]) ? toPrimitive(a[0], "string") : a[0]);
			if (nt == undef()) return (v : Dynamic);
			var o = wrap(v);
			o.proto = protoFrom(nt, StringProto);
			return o;
		});
		method(c, "fromCharCode", 1, (_, a, _) -> {
			var out = new StringBuf();
			for (v in a) out.addChar(toInt32(v) & 65535);
			return out.toString();});
		method(c, "fromCodePoint", 1, (_, a, _) -> {
			var out = new StringBuf();
			for (v in a) {
				var n = Seed.numeric(v);
				if (!Math.isFinite(n) || Math.ffloor(n) != n || n < 0 || n > 0x10ffff) error("RangeError", "Invalid code point " + Seed.text(v));
				var i = Std.int(n);
				if (i < 65536) out.addChar(i); else {
					i -= 65536;
					out.addChar(0xd800 + (i >> 10));
					out.addChar(0xdc00 + (i & 1023));
				}
			}
			return out.toString();});
		method(c, "raw", 1, (_, a, _) -> {
			var strings = get(arg(a, 0), "raw");
			var n = lengthOf(strings);
			var out = new StringBuf();
			var i:Float = 0;
			while (i < n) {
				out.add(Seed.text(get(strings, i)));
				if (i + 1 < n && i + 1 < a.length) out.add(Seed.text(a[Std.int(i + 1)]));
				i++;
			}
			return out.toString();});
		method(p, "toString", 0, (t, _, _) -> primitive(t, "string"));
		method(p, "valueOf", 0, (t, _, _) -> primitive(t, "string"));
		var names = ["charAt", "at", "charCodeAt", "codePointAt", "slice", "substring", "substr", "concat", "indexOf", "includes", "startsWith", "lastIndexOf", "endsWith",
			"toLowerCase", "toUpperCase", "toLocaleLowerCase", "toLocaleUpperCase", "trim", "trimStart", "trimEnd", "trimLeft", "trimRight", "repeat", "padStart", "padEnd",
			"split", "replace", "replaceAll", "localeCompare", "normalize", "isWellFormed", "toWellFormed", "search", "match", "matchAll"];
		for (name in names) method(p, name, stringArity(name), (t, a, _) -> stringMethod(thisString(t), name, a));
		// (read-only: compiled code calls it itself on a string, Seed.stringCharCodeAt)
		p.setOwn("charCodeAt", p.getOwn("charCodeAt"), Attr.HIDDEN | Attr.READONLY | Attr.LOCKED);
		method(p, Symbols.iterator, 0, (t, _, _) -> new JsIterator(StringIteratorProto, thisString(t), "values"));
	}

	static function stringArity(name:String):Int return switch (name) {
		case "toLowerCase" | "toUpperCase" | "toLocaleLowerCase" | "toLocaleUpperCase" | "trim" | "trimStart" | "trimEnd" | "trimLeft" | "trimRight" | "normalize" | "isWellFormed" | "toWellFormed": 0;
		case "slice" | "substring" | "substr" | "split" | "replace" | "replaceAll": 2;
		case _: 1;
	};

	public static function stringMethod(s:String, name:String, args:Array<Dynamic>):Dynamic {
		var first = arg(args, 0), second = arg(args, 1);
		var n = s.length;
		switch (name) {
			case "charAt" | "at" | "charCodeAt" | "codePointAt":
				var i = toIntegerOrInfinity(first);
				if (name == "at" && i < 0) i += n;
				if (i < 0 || i >= n) return name == "charAt" ? "" : name == "charCodeAt" ? Math.NaN : undef();
				var c = s.charCodeAt(Std.int(i));
				if (name == "codePointAt" && c >= 0xd800 && c <= 0xdbff && i + 1 < n) {
					var d = s.charCodeAt(Std.int(i + 1));
					if (d >= 0xdc00 && d <= 0xdfff) return (c - 0xd800) * 1024 + (d - 0xdc00) + 65536;
				}
				return name == "charCodeAt" || name == "codePointAt" ? c : s.charAt(Std.int(i));
			case "slice":
				var start = relative(first, n), end = second == undef() ? n : relative(second, n);
				return s.substring(Std.int(start), Std.int(Math.max(start, end)));
			case "substring":
				var start = Math.max(0, Math.min(toIntegerOrInfinity(first), n)), end = second == undef() ? n : Math.max(0, Math.min(toIntegerOrInfinity(second), n));
				return s.substring(Std.int(Math.min(start, end)), Std.int(Math.max(start, end)));
			case "substr":
				var start = relative(first, n);
				var length = second == undef() ? n - start : Math.min(Math.max(toIntegerOrInfinity(second), 0), n - start);
				return length <= 0 ? "" : s.substr(Std.int(start), Std.int(length));
			case "concat":
				var b = new StringBuf();
				b.add(s);
				for (a in args) b.add(Seed.text(a));
				return b.toString();
			case "indexOf" | "includes" | "startsWith":
				if (name != "indexOf" && Regex.isRegExp(first)) error("TypeError", "First argument to String.prototype." + name + " must not be a regular expression");
				var needle = Seed.text(first);
				var start = Std.int(Math.max(0, Math.min(toIntegerOrInfinity(second), n)));
				if (name == "startsWith") return s.substr(start, needle.length) == needle;
				var i = s.indexOf(needle, start);
				return name == "indexOf" ? i : i >= 0;
			case "lastIndexOf":
				var num = Seed.numeric(second);
				var pos = Math.isNaN(num) ? n : Std.int(Math.max(0, Math.min(toIntegerOrInfinity(num), n)));
				return s.lastIndexOf(Seed.text(first), Std.int(pos));
			case "endsWith":
				if (Regex.isRegExp(first)) error("TypeError", "First argument to String.prototype.endsWith must not be a regular expression");
				var needle = Seed.text(first);
				var end = second == undef() ? n : Std.int(Math.max(0, Math.min(toIntegerOrInfinity(second), n)));
				return end >= needle.length && s.substr(end - needle.length, needle.length) == needle;
			case "toLowerCase" | "toLocaleLowerCase": return s.toLowerCase();
			case "toUpperCase" | "toLocaleUpperCase": return s.toUpperCase();
			case "trim" | "trimStart" | "trimEnd" | "trimLeft" | "trimRight":
				var start = 0, end = n;
				if (name != "trimEnd" && name != "trimRight") while (start < end && Seed.whitespace(s.charCodeAt(start))) start++;
				if (name != "trimStart" && name != "trimLeft") while (end > start && Seed.whitespace(s.charCodeAt(end - 1))) end--;
				return s.substring(start, end);
			case "repeat":
				var count = toIntegerOrInfinity(first);
				if (count < 0 || !Math.isFinite(count)) error("RangeError", "Invalid count value: " + Seed.text(first));
				if (count * s.length > 536870888) error("RangeError", "Invalid string length");
				var b = new StringBuf();
				var i:Float = 0;
				while (i < count) {
					b.add(s);
					i++;
				}
				return b.toString();
			case "padStart" | "padEnd":
				var target = toIntegerOrInfinity(first);
				var fill = second == undef() ? " " : Seed.text(second);
				if (target <= n || fill == "") return s;
				if (target > 536870888) error("RangeError", "Invalid string length");
				var padding = new StringBuf();
				var needed = Std.int(target - n);
				while (padding.length < needed) padding.add(fill);
				var pad = padding.toString().substr(0, needed);
				return name == "padStart" ? pad + s : s + pad;
			case "localeCompare": return collate(s, Seed.text(first));
			case "normalize":
				var form = first == undef() ? "NFC" : Seed.text(first);
				if (["NFC", "NFD", "NFKC", "NFKD"].indexOf(form) < 0) return error("RangeError", "Invalid normalization form");
				return normalizeString(s, form);
			case "isWellFormed" | "toWellFormed":
				var b = new StringBuf();
				var ok = true;
				var i = 0;
				while (i < n) {
					var c = s.charCodeAt(i);
					if (c >= 0xd800 && c <= 0xdbff && i + 1 < n && s.charCodeAt(i + 1) >= 0xdc00 && s.charCodeAt(i + 1) <= 0xdfff) {
						b.addChar(c);
						b.addChar(s.charCodeAt(i + 1));
						i += 2;
						continue;
					}
					if (c >= 0xd800 && c <= 0xdfff) {
						ok = false;
						b.addChar(0xfffd);
					} else b.addChar(c);
					i++;
				}
				return name == "isWellFormed" ? ok : b.toString();
			case "split":
				if (first != null && first != undef()) {
					var splitter = getKey(first, "\x00@@split", first);
					if (splitter != undef() && splitter != null) return call(splitter, first, [s, second]);
				}
				var limit = second == undef() ? 4294967295.0 : toUint32(second);
				var out = new JsArray(ArrayProto);
				if (limit == 0) return out;
				if (first == undef()) {
					setIndex(out, 0, s);
					return out;
				}
				var delimiter = Seed.text(first);
				if (delimiter == "") {
					var i = 0;
					while (i < n && out.length < limit) setIndex(out, out.length, s.charAt(i++));
					return out;
				}
				var start = 0;
				while (out.length < limit) {
					var i = s.indexOf(delimiter, start);
					if (i < 0) {
						setIndex(out, out.length, s.substr(start));
						break;
					}
					setIndex(out, out.length, s.substring(start, i));
					start = i + delimiter.length;
				}
				return out;
			case "replace" | "replaceAll":
				if (first != null && first != undef()) {
					if (name == "replaceAll" && Regex.isRegExp(first) && Seed.text(get(first, "flags")).indexOf("g") < 0) error("TypeError", "replaceAll must be called with a global RegExp");
					var replacer = getKey(first, "\x00@@replace", first);
					if (replacer != undef() && replacer != null) return call(replacer, first, [s, second]);
				}
				var search = Seed.text(first);
				var functional = isCallable(second);
				var replacement = functional ? "" : Seed.text(second);
				var b = new StringBuf();
				var start = 0;
				var pos = s.indexOf(search);
				while (pos >= 0) {
					b.add(s.substring(start, pos));
					b.add(functional ? Seed.text(call(second, undef(), [search, pos, s])) : Regex.expand(replacement, search, s, pos, [], null));
					start = pos + search.length;
					if (name == "replace") break;
					if (search == "") {
						if (pos >= n) break;
						b.add(s.charAt(pos));
						start = pos + 1;
					}
					pos = s.indexOf(search, start);
				}
				b.add(s.substr(start));
				return b.toString();
			case "search" | "match" | "matchAll":
				var symbol = name == "search" ? "\x00@@search" : name == "match" ? "\x00@@match" : "\x00@@matchAll";
				if (first != null && first != undef()) {
					if (name == "matchAll" && Regex.isRegExp(first) && Seed.text(get(first, "flags")).indexOf("g") < 0) error("TypeError", "String.prototype.matchAll called with a non-global RegExp argument");
					var m = getKey(first, symbol, first);
					if (m != undef() && m != null) return call(m, first, [s]);
				}
				var re = createRegExp(first == undef() ? "" : Seed.text(first), name == "matchAll" ? "g" : "");
				return call(get(re, symbol), re, [s]);
			case _: return error("TypeError", "String.prototype." + name + " is not implemented");
		}
	}

	// localeCompare: an approximation of ICU's root collation in three levels:
	// base characters (punctuation, then digits, then letters with Latin
	// accents folded), then accents, then case (lowercase first).
	static var accents = "ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÝýÿÑñÇç";
	static var bases = "AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuYyyNnCc";
	static function baseOf(c:Int):Int {
		var k = accents.indexOf(String.fromCharCode(c));
		return k >= 0 ? bases.charCodeAt(k) : c;
	}

	static function primary(c:Int):Int {
		var b = baseOf(c);
		if (b >= 65 && b <= 90) b += 32;
		if (b >= 97 && b <= 122) return 30000 + b;
		if (b >= 48 && b <= 57) return 20000 + b;
		if (b >= 0xc0) return 40000 + String.fromCharCode(b).toLowerCase().charCodeAt(0);
		return 10000 + b;
	}

	public static function collate(a:String, b:String):Int {
		var n = Std.int(Math.min(a.length, b.length));
		for (i in 0...n) {
			var x = primary(a.charCodeAt(i)), y = primary(b.charCodeAt(i));
			if (x != y) return x < y ? -1 : 1;
		}
		if (a.length != b.length) return a.length < b.length ? -1 : 1;
		for (i in 0...n) {
			var x = a.charCodeAt(i), y = b.charCodeAt(i);
			var ax = baseOf(x) != x, ay = baseOf(y) != y;
			if (ax != ay) return ax ? 1 : -1;
		}
		for (i in 0...n) {
			var x = a.charCodeAt(i), y = b.charCodeAt(i);
			if (x == y) continue;
			var lx = String.fromCharCode(x).toLowerCase().charCodeAt(0) == x, ly = String.fromCharCode(y).toLowerCase().charCodeAt(0) == y;
			if (lx != ly) return lx ? -1 : 1;
		}
		return compareStrings(a, b) < 0 ? -1 : compareStrings(a, b) > 0 ? 1 : 0;
	}
}
