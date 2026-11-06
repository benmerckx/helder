package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Symbols.JsSymbol;
import helder.typescript.js.Lib.*;
import helder.typescript.js.Builtins.*;
import helder.typescript.js.Objects.*;
import helder.typescript.js.Arrays.*;
import helder.typescript.js.Strings.*;
import helder.typescript.js.Collections.*;

// The global object's functions and namespaces: globalThis, Math, Reflect, the URI functions, structuredClone, template objects, the test harness's globals.
@:access(helder.typescript.js.Builtins)
@:access(helder.typescript.js.Objects)
@:access(helder.typescript.js.Arrays)
@:access(helder.typescript.js.Strings)
@:access(helder.typescript.js.Collections)
class Globals {
	public static function templateObject(cooked:Array<Dynamic>, raw:Array<Dynamic>):Dynamic {
		var r = array(raw);
		integrity(r, true);
		var a:JsArray = cast array(cooked);
		a.setOwn("raw", r, Attr.HIDDEN | Attr.READONLY | Attr.LOCKED);
		integrity(a, true);
		return a;
	}

	// structuredClone: plain data, arrays, Map/Set, Date, RegExp and errors; shared and cyclic references kept.
	static function clone(v:Dynamic, seen:haxe.ds.ObjectMap<Dynamic, Dynamic>):Dynamic {
		if (Std.isOfType(v, Symbols.JsSymbol)) error("DataCloneError", Symbols.text(v) + " could not be cloned.");
		if (!isObject(v)) return v;
		if (seen.exists(v)) return seen.get(v);
		if (Std.isOfType(v, JsFunction)) error("DataCloneError", Inspect.inspect(v) + " could not be cloned.");
		if (Std.isOfType(v, Dates.JsDate)) {
			var d = Dates.make((v : Dates.JsDate).time);
			seen.set(v, d);
			return d;
		}
		if (Regex.isRegExp(v)) {
			var r:Regex.JsRegExp = cast v;
			var c = Regex.compile(r.source, r.flags);
			seen.set(v, c);
			return c;
		}
		if (Std.isOfType(v, JsMap)) {
			var m:JsMap = cast v;
			var c = new JsMap(m.isSet ? SetProto : MapProto, m.isSet);
			seen.set(v, c);
			for (i in 0...m.keys.length) if (m.active[i]) mapPut(c, clone(m.keys[i], seen), clone(m.values[i], seen));
			return c;
		}
		if (Std.isOfType(v, JsArray)) {
			var a:JsArray = cast v;
			var c = new JsArray(ArrayProto);
			seen.set(v, c);
			c.length = a.length;
			for (k in keys(a)) defineOwn(c, k, clone(get(a, k), seen));
			return c;
		}
		var o:JsObject = v;
		var c = Std.isOfType(v, JsError) ? new JsError(o.proto) : new JsObject(ObjectProto);
		seen.set(v, c);
		if (Std.isOfType(v, JsError)) for (k in ["message", "name", "cause"]) if (o.hasOwn(k)) c.setOwn(k, clone(o.getOwn(k), seen), Attr.HIDDEN);
		for (k in keys(o)) c.setOwn(k, clone(get(o, k), seen));
		return c;
	}

	// encodeURI(Component): UTF-8 escapes for characters outside the unreserved set.
	static function encodeUri(s:String, keep:String):String {
		var out = new StringBuf();
		var i = 0;
		while (i < s.length) {
			var c = s.charCodeAt(i);
			if (c < 128 && (c >= 48 && c <= 57 || c >= 65 && c <= 90 || c >= 97 && c <= 122 || keep.indexOf(String.fromCharCode(c)) >= 0)) {
				out.addChar(c);
				i++;
				continue;
			}
			var cp = c;
			if (c >= 0xdc00 && c <= 0xdfff) error("URIError", "URI malformed");
			if (c >= 0xd800 && c <= 0xdbff) {
				var d = i + 1 < s.length ? s.charCodeAt(i + 1) : 0;
				if (d < 0xdc00 || d > 0xdfff) error("URIError", "URI malformed");
				cp = (c - 0xd800) * 1024 + (d - 0xdc00) + 0x10000;
				i++;
			}
			i++;
			var bytes = cp < 0x80 ? [cp] : cp < 0x800 ? [0xc0 | (cp >> 6), 0x80 | (cp & 63)] : cp < 0x10000 ? [0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63)] : [0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 63), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63)];
			for (b in bytes) out.add("%" + StringTools.hex(b, 2));
		}
		return out.toString();
	}

	static function decodeUri(s:String, reserved:String):String {
		var out = new StringBuf();
		var i = 0;
		function hexAt(k:Int):Int {
			if (k + 2 >= s.length + 0 && k + 2 > s.length) return -1;
			var h = s.substr(k + 1, 2);
			if (h.length < 2 || s.charAt(k) != "%") return -1;
			var v = 0;
			for (j in 0...2) {
				var c = h.charCodeAt(j);
				var d = c >= 48 && c <= 57 ? c - 48 : c >= 65 && c <= 70 ? c - 55 : c >= 97 && c <= 102 ? c - 87 : -1;
				if (d < 0) return -1;
				v = v * 16 + d;
			}
			return v;
		}
		while (i < s.length) {
			var c = s.charAt(i);
			if (c != "%") {
				out.add(c);
				i++;
				continue;
			}
			var b = hexAt(i);
			if (b < 0) error("URIError", "URI malformed");
			if (b < 0x80) {
				var ch = String.fromCharCode(b);
				out.add(reserved.indexOf(ch) >= 0 ? s.substr(i, 3) : ch);
				i += 3;
				continue;
			}
			var n = b >= 0xf0 ? 4 : b >= 0xe0 ? 3 : b >= 0xc0 ? 2 : 0;
			if (n == 0) error("URIError", "URI malformed");
			var cp = b & (0xff >> (n + 1));
			var start = i;
			i += 3;
			for (_ in 1...n) {
				var x = hexAt(i);
				if (x < 0 || x & 0xc0 != 0x80) error("URIError", "URI malformed");
				cp = (cp << 6) | (x & 63);
				i += 3;
			}
			if (cp > 0x10ffff || cp >= 0xd800 && cp <= 0xdfff || n == 2 && cp < 0x80 || n == 3 && cp < 0x800 || n == 4 && cp < 0x10000) error("URIError", "URI malformed");
			if (cp < 0x10000) out.addChar(cp); else {
				cp -= 0x10000;
				out.addChar(0xd800 + (cp >> 10));
				out.addChar(0xdc00 + (cp & 1023));
			}
		}
		return out.toString();
	}

	// Globals: functions, Math, console, Reflect, globalThis and the Test262 harness.
	static function setupGlobals():Void {
		globals.set("undefined", undef());
		globals.set("NaN", Math.NaN);
		globals.set("Infinity", Math.POSITIVE_INFINITY);
		var number:JsObject = globals.get("Number");
		var parseIntFn = native("parseInt", 2, (_, a, _) -> Numbers.parseInteger(Seed.text(arg(a, 0)), arg(a, 1)));
		var parseFloatFn = native("parseFloat", 1, (_, a, _) -> Numbers.parseDecimalPrefix(Seed.text(arg(a, 0))));
		globals.set("parseInt", parseIntFn);
		globals.set("parseFloat", parseFloatFn);
		number.setOwn("parseInt", parseIntFn, Attr.HIDDEN);
		number.setOwn("parseFloat", parseFloatFn, Attr.HIDDEN);
		globals.set("isNaN", native("isNaN", 1, (_, a, _) -> Math.isNaN(Seed.numeric(arg(a, 0)))));
		globals.set("isFinite", native("isFinite", 1, (_, a, _) -> Math.isFinite(Seed.numeric(arg(a, 0)))));
		var math = new JsObject(ObjectProto);
		globals.set("Math", math);
		math.setOwn(Symbols.toStringTag, "Math", Attr.HIDDEN | Attr.READONLY);
		constant(math, "PI", Math.PI);
		constant(math, "E", Math.exp(1));
		constant(math, "LN2", Math.log(2));
		constant(math, "LN10", Math.log(10));
		constant(math, "LOG2E", 1 / Math.log(2));
		constant(math, "LOG10E", 1 / Math.log(10));
		constant(math, "SQRT2", Math.sqrt(2));
		constant(math, "SQRT1_2", Math.sqrt(0.5));
		for (name in ["abs", "floor", "ceil", "trunc", "round", "sqrt", "cbrt", "sin", "cos", "tan", "asin", "acos", "atan", "exp", "expm1", "log", "log1p", "log2", "log10", "sign", "fround", "f16round", "clz32", "sinh", "cosh", "tanh", "asinh", "acosh", "atanh"])
			method(math, name, 1, (_, a, _) -> Numbers.math(name, Seed.numeric(arg(a, 0)), 0));
		for (name in ["pow", "atan2", "imul"]) method(math, name, 2, (_, a, _) -> name == "imul" ? toInt32(arg(a, 0)) * toInt32(arg(a, 1)) : Numbers.math(name, Seed.numeric(arg(a, 0)), Seed.numeric(arg(a, 1))));
		method(math, "random", 0, (_, _, _) -> Math.random());
		for (name in ["min", "max", "hypot"]) method(math, name, 2, (_, a, _) -> {
			var values = [for (v in a) Seed.numeric(v)];
			if (name == "hypot") {
				var sum = 0.0;
				var inf = false;
				var nan = false;
				for (n in values) {
					if (!Math.isFinite(n) && !Math.isNaN(n)) inf = true;
					if (Math.isNaN(n)) nan = true;
					sum += n * n;
				}
				return inf ? Math.POSITIVE_INFINITY : nan ? Math.NaN : Math.sqrt(sum);
			}
			var result = name == "min" ? Math.POSITIVE_INFINITY : Math.NEGATIVE_INFINITY;
			for (n in values) {
				if (Math.isNaN(n)) return Math.NaN;
				if (name == "min" ? (n < result || n == 0 && result == 0 && 1 / n < 0) : (n > result || n == 0 && result == 0 && 1 / n > 0)) result = n;
			}
			return result;
		});
		// (frozen: compiled code calls Math's functions itself, so replacing
		// one is a TypeError rather than a change the code would not see)
		integrity(math, true);
		var console = new JsObject(ObjectProto);
		globals.set("console", console);
		for (name in ["log", "info", "debug", "error", "warn", "trace"]) method(console, name, 0, (_, a, _) -> {
			var line = Inspect.format(a);
			if (name == "error" || name == "warn" || name == "trace") Sys.stderr().writeString(line + "\n"); else Seed.print(line + "\n");
			return undef();
		});
		var reflect = new JsObject(ObjectProto);
		globals.set("Reflect", reflect);
		reflect.setOwn(Symbols.toStringTag, "Reflect", Attr.HIDDEN | Attr.READONLY);
		method(reflect, "ownKeys", 1, (_, a, _) -> {
			var o = arg(a, 0);
			if (!isObject(o)) error("TypeError", "Reflect.ownKeys called on non-object");
			return array([for (k in ownPropertyKeys(o)) Symbols.isSymbolKey(k) && Symbols.fromKey(k) != null ? (Symbols.fromKey(k) : Dynamic) : k]);});
		method(reflect, "has", 2, (_, a, _) -> has(arg(a, 0), arg(a, 1)));
		method(reflect, "get", 2, (_, a, _) -> {
			var o = arg(a, 0);
			if (!isObject(o)) error("TypeError", "Reflect.get called on non-object");
			return getKey(o, key(arg(a, 1)), a.length > 2 ? a[2] : o);});
		method(reflect, "set", 3, (_, a, _) -> {
			try {
				put(arg(a, 0), arg(a, 1), arg(a, 2));
				return true;
			} catch (e:Dynamic) {
				return false;
			}});
		method(reflect, "apply", 3, (_, a, _) -> call(arg(a, 0), arg(a, 1), arrayLikeList(arg(a, 2))));
		method(reflect, "construct", 2, (_, a, _) -> construct(arg(a, 0), arrayLikeList(arg(a, 1)), a.length > 2 ? a[2] : arg(a, 0)));
		method(reflect, "getPrototypeOf", 1, (_, a, _) -> (arg(a, 0) : JsObject).proto);
		method(reflect, "setPrototypeOf", 2, (_, a, _) -> {
			setPrototype(arg(a, 0), arg(a, 1));
			return true;});
		method(reflect, "defineProperty", 3, (_, a, _) -> {
			try {
				defineProperty(arg(a, 0), key(arg(a, 1)), arg(a, 2));
				return true;
			} catch (e:Dynamic) {
				return false;
			}});
		method(reflect, "deleteProperty", 2, (_, a, _) -> {
			try {
				return remove(arg(a, 0), arg(a, 1));
			} catch (e:Dynamic) {
				return false;
			}});
		method(reflect, "getOwnPropertyDescriptor", 2, (_, a, _) -> descriptor(arg(a, 0), key(arg(a, 1))));
		method(reflect, "isExtensible", 1, (_, a, _) -> (arg(a, 0) : JsObject).extensible);
		method(reflect, "preventExtensions", 1, (_, a, _) -> {
			(arg(a, 0) : JsObject).extensible = false;
			return true;});
		// Test262 harness (assert.js, sta.js, compareArray.js)
		var assert = native("assert", 2, (_, a, _) -> {
			if (arg(a, 0) != true) error("Test262Error", arg(a, 1) == undef() ? "Expected true but got " + Seed.text(arg(a, 0)) : Seed.text(arg(a, 1)));
			return undef();});
		globals.set("assert", assert);
		method(assert, "sameValue", 2, (_, a, _) -> {
			if (!sameValue(arg(a, 0), arg(a, 1))) error("Test262Error", (arg(a, 2) == undef() ? "" : Seed.text(arg(a, 2)) + " ") + "Expected SameValue(" + Inspect.format([arg(a, 0)]) + ", " + Inspect.format([arg(a, 1)]) + ") to be true");
			return undef();});
		method(assert, "notSameValue", 2, (_, a, _) -> {
			if (sameValue(arg(a, 0), arg(a, 1))) error("Test262Error", (arg(a, 2) == undef() ? "" : Seed.text(arg(a, 2)) + " ") + "Expected SameValue to be false");
			return undef();});
		method(assert, "throws", 2, (_, a, _) -> {
			var expected = arg(a, 0);
			var f = callback(arg(a, 1));
			var caught = false;
			try call(f, undef(), []) catch (e:Dynamic) {
				caught = true;
				if (!isObject(e) || get(e, "constructor") != expected) error("Test262Error", "Expected a " + Seed.text(get(expected, "name")) + " to be thrown but got " + (isObject(e) ? Seed.text(get(get(e, "constructor"), "name")) : Seed.text(e)));
			}
			if (!caught) error("Test262Error", "Expected a " + Seed.text(get(expected, "name")) + " to be thrown but no exception was thrown at all");
			return undef();
		});
		method(assert, "compareArray", 2, (_, a, _) -> {
			var x = arg(a, 0), y = arg(a, 1);
			var same = lengthOf(x) == lengthOf(y);
			var i:Float = 0;
			while (same && i < lengthOf(x)) {
				if (!sameValue(get(x, i), get(y, i))) same = false;
				i++;
			}
			if (!same) error("Test262Error", "Actual " + Inspect.format([x]) + " and expected " + Inspect.format([y]) + " should have the same contents. " + (arg(a, 2) == undef() ? "" : Seed.text(arg(a, 2))));
			return undef();
		});
		globals.set("$EXPECT_ASYNC", native("$EXPECT_ASYNC", 0, (_, _, _) -> {
			asyncExpected = true;
			asyncDone = 0;
			return undef();}));
		globals.set("$DONE", native("$DONE", 1, (_, a, _) -> {
			if (arg(a, 0) != undef()) throw arg(a, 0);
			if (++asyncDone != 1) error("Test262Error", "$DONE called more than once");
			return undef();}));
		globals.set("$ERROR", native("$ERROR", 1, (_, a, _) -> error("Test262Error", Seed.text(arg(a, 0)))));
		globals.set("$DONOTEVALUATE", native("$DONOTEVALUATE", 0, (_, _, _) -> error("Test262Error", "Test262: This statement should not be evaluated.")));
		var harness = new JsObject(ObjectProto);
		method(harness, "detachArrayBuffer", 1, (_, a, _) -> Buffers.detach(arg(a, 0)));
		globals.set("$262", harness);
		var globalObject = new JsObject(ObjectProto);
		globals.set("globalThis", globalObject);
		for (name => v in globals) if (name != "globalThis") globalObject.setOwn(name, v, Attr.HIDDEN);
	}
}
