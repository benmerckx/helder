package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Symbols.JsSymbol;
import helder.typescript.js.Async.JsGenerator;

// Only the semantics/runtime is Haxe. No TypeScript source passes through the Haxe typer.
class Undefined {
	public function new() {}
}

class Seed {
	public static var undefinedValue:Dynamic = new Undefined();
	public static function getUndefined():Dynamic return undefinedValue;

	public static function consoleNumber(v:Float):String return v == 0 && 1 / v < 0 ? "-0" : numberText(v);

	public static function consoleText(v:Dynamic):String return Std.isOfType(v, String) ? v : Inspect.inspect(v);

	// (JS's ** differs from pow for a NaN exponent and for ±1 to an infinite power)
	public static function power(a:Float, b:Float):Float {
		if (Math.isNaN(b)) return Math.NaN;
		if (b == 0) return 1;
		if ((a == 1 || a == -1) && !Math.isFinite(b)) return Math.NaN;
		return Math.pow(a, b);
	}

	public static function modulo(a:Float, b:Float):Float {
		// Integral int32 operands take an exact integer remainder (the sign follows
		// the dividend, as in JS; 0*a gives -0 for negative dividends). Others use fmod.
		var d = b < 0 ? -b : b;
		if (a >= -2147483647.0 && a <= 2147483647.0 && d >= 1.0 && d <= 2147483647.0) {
			var x = Std.int(a), y = Std.int(d);
			if (x == a && y == d) {
				var r = x % y;
				return r == 0 ? 0 * a : r;
			}
		}
		return a % b;
	}

	public static function numberText(v:Float):String {
		if (v == 0) return "0";
		return Std.string(v);
	}

	public static function text(v:Dynamic):String {
		if (v == undefinedValue) return "undefined";
		if (v == null) return "null";
		if (Std.isOfType(v, Bool)) return v ? "true" : "false";
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return numberText(v);
		if (Std.isOfType(v, String)) return v;
		if (Std.isOfType(v, Symbols.JsSymbol)) return Lib.error("TypeError", "Cannot convert a Symbol value to a string");
		if (Lib.isObject(v)) return text(Lib.toPrimitive(v, "string"));
		return Std.string(v);
	}

	public static function truth(v:Dynamic):Bool {
		if (v == null || v == undefinedValue) return false;
		if (Std.isOfType(v, Bool)) return v;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) {
			var n:Float = v;
			return n != 0 && !Math.isNaN(n);
		}
		if (Std.isOfType(v, String)) {
			var s:String = v;
			return s.length > 0;
		}
		return true;
	}

	public static function typeOf(v:Dynamic):String {
		if (v == undefinedValue) return "undefined";
		if (v == null) return "object";
		if (Std.isOfType(v, Bool)) return "boolean";
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return "number";
		if (Std.isOfType(v, String)) return "string";
		if (Std.isOfType(v, Symbols.JsSymbol)) return "symbol";
		if (Std.isOfType(v, JsFunction)) return "function";
		return "object";
	}

	public static function strictEq(a:Dynamic, b:Dynamic):Bool {
		// (numbers by value, NaN unequal; strings by value; the rest by identity)
		if (Std.isOfType(a, Float)) {
			if (!Std.isOfType(b, Float)) return false;
			var x:Float = a, y:Float = b;
			return x == y;
		}
		return !Std.isOfType(b, Float) && a == b;
	}

	public static function looseEq(a:Dynamic, b:Dynamic):Bool {
		var nullishA = a == null || a == undefinedValue, nullishB = b == null || b == undefinedValue;
		if (nullishA || nullishB) return nullishA && nullishB;
		var ta = typeOf(a), tb = typeOf(b);
		if (ta == tb || ta == "function" && tb == "object" || ta == "object" && tb == "function") return strictEq(a, b);
		if (ta == "boolean") return looseEq(numeric(a), b);
		if (tb == "boolean") return looseEq(a, numeric(b));
		if (Lib.isObject(a)) return looseEq(Lib.toPrimitive(a, "default"), b);
		if (Lib.isObject(b)) return looseEq(a, Lib.toPrimitive(b, "default"));
		if (ta == "symbol" || tb == "symbol") return false;
		return numeric(a) == numeric(b);
	}

	public static function numeric(v:Dynamic):Float {
		if (v == undefinedValue) return Math.NaN;
		if (v == null) return 0;
		if (Std.isOfType(v, Bool)) return v ? 1 : 0;
		if (Std.isOfType(v, String)) return numberFromString(v);
		if (Std.isOfType(v, Symbols.JsSymbol)) return Lib.error("TypeError", "Cannot convert a Symbol value to a number");
		if (Lib.isObject(v)) return numeric(Lib.toPrimitive(v, "number"));
		return v;
	}

	public static function whitespace(c:Int):Bool {
		return c >= 9 && c <= 13 || c == 32 || c == 160 || c == 5760 || c >= 8192 && c <= 8202 || c == 8232 || c == 8233 || c == 8239 || c == 8287 || c == 12288 || c == 65279;
	}

	static function numberFromString(value:String):Float {
		var start = 0;
		var end = value.length;
		while (start < end && whitespace(value.charCodeAt(start))) start++;
		while (end > start && whitespace(value.charCodeAt(end - 1))) end--;
		var s = value.substring(start, end);
		if (s == "") return 0;
		if (s == "Infinity" || s == "+Infinity") return Math.POSITIVE_INFINITY;
		if (s == "-Infinity") return Math.NEGATIVE_INFINITY;
		if (s.length >= 2 && s.charAt(0) == "0") {
			var prefix = s.charAt(1).toLowerCase();
			if (prefix == "x" || prefix == "o" || prefix == "b") {
				if (s.length == 2) return Math.NaN;
				var radix = prefix == "x" ? 16 : prefix == "o" ? 8 : 2;
				// Convert radix-prefixed input exactly to decimal before parsing.
				var limbs:Array<Int> = [0];
				for (i in 2...s.length) {
					var c = s.charCodeAt(i);
					var digit = c >= 48 && c <= 57 ? c - 48 : c >= 65 && c <= 70 ? c - 55 : c >= 97 && c <= 102 ? c - 87 : -1;
					if (digit < 0 || digit >= radix) return Math.NaN;
					var carry = digit;
					for (j in 0...limbs.length) {
						var n = limbs[j] * radix + carry;
						limbs[j] = n % 10000000;
						carry = Std.int(n / 10000000);
					}
					if (carry > 0) limbs.push(carry);
				}
				var decimal = new StringBuf();
				decimal.add(limbs[limbs.length - 1]);
				var i = limbs.length - 1;
				while (i > 0) {
					var part = Std.string(limbs[--i]);
					while (part.length < 7) part = "0" + part;
					decimal.add(part);
				}
				return Std.parseFloat(decimal.toString());
			}
		}
		var i = 0;
		if (s.charAt(i) == "+" || s.charAt(i) == "-") i++;
		var digits = 0;
		while (i < s.length && s.charCodeAt(i) >= 48 && s.charCodeAt(i) <= 57) {
			i++;
			digits++;
		}
		if (s.charAt(i) == ".") {
			i++;
			while (i < s.length && s.charCodeAt(i) >= 48 && s.charCodeAt(i) <= 57) {
				i++;
				digits++;
			}
		}
		if (digits == 0) return Math.NaN;
		if (s.charAt(i) == "e" || s.charAt(i) == "E") {
			i++;
			if (s.charAt(i) == "+" || s.charAt(i) == "-") i++;
			var exponentStart = i;
			while (i < s.length && s.charCodeAt(i) >= 48 && s.charCodeAt(i) <= 57) i++;
			if (i == exponentStart) return Math.NaN;
		}
		return i == s.length ? Std.parseFloat(s) : Math.NaN;
	}

	public static function add(a:Dynamic, b:Dynamic):Dynamic {
		if (Lib.isObject(a)) a = Lib.toPrimitive(a, "default");
		if (Lib.isObject(b)) b = Lib.toPrimitive(b, "default");
		if (Std.isOfType(a, String) || Std.isOfType(b, String)) return text(a) + text(b);
		return numeric(a) + numeric(b);
	}

	public static function concat(a:String, b:String):String return a + b;

	public static function stringEq(a:String, b:String):Bool return a == b;

	public static function stringLength(a:String):Float return a.length;

	public static function print(s:String):Void Sys.print(s);

	public static function consoleLine(values:Array<Dynamic>):String return Inspect.format(values);

	public static function uncaught(e:Dynamic):Void {
		var text = try (Lib.isObject(e) && Std.isOfType(e, JsError) ? "Uncaught " + Builtins.errorText(e) : "Uncaught " + Inspect.inspect(e)) catch (_:Dynamic) "Uncaught exception";
		Sys.stderr().writeString(text + "\n");
		Sys.exit(1);
	}

	// Entry points for compiled code (see Frontend).
	public static function libInit():Void Builtins.init();

	// (the built-ins a program uses: Builtins.install*, chosen by lower.Features)
	public static function libInstallRegExp():Void Builtins.installRegExp();

	public static function libInstallNormalize():Void Builtins.installNormalize();

	public static function libInstallDate():Void Builtins.installDate();

	public static function libInstallBuffers():Void Builtins.installBuffers();

	public static function libInstallJson():Void Builtins.installJson();

	public static function libInstallIteratorHelpers():Void Builtins.installIteratorHelpers();

	public static function libInstallPromise():Void Builtins.installPromise();

	public static function libInstallFromAsync():Void Builtins.installFromAsync();

	public static function libInstallSetMethods():Void Builtins.installSetMethods();

	public static function libInstallUri():Void Builtins.installUri();

	public static function libInstallStructuredClone():Void Builtins.installStructuredClone();

	public static function libInstallAll():Void Builtins.installAll();

	public static function libTypeofGlobal(name:String):String return Builtins.globals.exists(name) ? typeOf(Builtins.globals.get(name)) : "undefined";

	public static function libTypeofNamespace(ns:Dynamic, name:String):String return Lib.hasOwnKey(ns, name) ? typeOf(Lib.get(ns, name)) : libTypeofGlobal(name);

	public static function libGlobal(name:String):Dynamic return Builtins.global(name);

	public static function libFunction(impl:Dynamic, arity:Int, rest:Bool, kind:Int, name:String):Dynamic return Lib.makeFunction(impl, arity, rest, kind, name);

	public static function libClass(name:String, parent:Dynamic, impl:Dynamic, arity:Int, rest:Bool, fields:Dynamic):Dynamic return Lib.makeClass(name, parent, impl, arity, rest, fields);

	// A value its type does not describe, where the program relies on it
	// (strict lowering: values in typed slots are what their types say).
	public static function diverge(expected:String, v:Dynamic, where:String):Dynamic
		return Lib.error("TypeError", where + ": TSHX100: " + Lib.describe(v) + " is not " + expected + " (its TypeScript type does not describe it)");

	// a value into a number slot
	public static function expectNumber(v:Dynamic, where:String):Float {
		if (Std.isOfType(v, Float)) return v;
		diverge("a number", v, where);
		return 0;
	}

	// a value into a boolean slot
	public static function expectBoolean(v:Dynamic, where:String):Bool {
		if (Std.isOfType(v, Bool)) return v;
		diverge("a boolean", v, where);
		return false;
	}

	// a value into a string slot
	public static function expectString(v:Dynamic, where:String):String {
		if (Std.isOfType(v, String)) return v;
		diverge("a string", v, where);
		return "";
	}

	// a string a loop only appends to, built in a buffer (the frontend: s += x)
	public static function libBuffer(s:String):StringBuf {
		var b = new StringBuf();
		b.add(s);
		return b;
	}

	public static function libBufferAdd(b:StringBuf, s:String):Void b.add(s);

	public static function libBuffered(b:StringBuf):String return b.toString();

	// String.prototype.charCodeAt on a string (read-only: Builtins)
	public static function stringCharCodeAt(s:String, pos:Float):Float {
		var i = Math.isNaN(pos) ? 0 : pos < 0 ? Math.fceil(pos) : Math.ffloor(pos);
		return i < 0 || i >= s.length ? Math.NaN : StringTools.fastCodeAt(s, Std.int(i));
	}

	// Math's functions called directly (the frontend: Math.f(...) where the program replaces neither)
	public static function mathSqrt(a:Float):Float return Math.sqrt(a);

	public static function mathAbs(a:Float):Float return Math.abs(a);

	public static function mathFloor(a:Float):Float return Math.ffloor(a);

	public static function mathCeil(a:Float):Float return Math.fceil(a);

	public static function mathUnary(name:String, a:Float):Float return Numbers.math(name, a, 0);

	public static function mathBinary(name:String, a:Float, b:Float):Float return Numbers.math(name, a, b);

	public static function mathMin(a:Float, b:Float):Float return Math.isNaN(a) || Math.isNaN(b) ? Math.NaN : a < b || a == 0 && b == 0 && 1 / a < 0 ? a : b;

	public static function mathMax(a:Float, b:Float):Float return Math.isNaN(a) || Math.isNaN(b) ? Math.NaN : a > b || a == 0 && b == 0 && 1 / a > 0 ? a : b;

	// for-of over an array: the array iterator, unchanged, steps through it by index
	public static function libArrayIterable(o:Dynamic):Bool return (o : JsArray).proto == Builtins.ArrayProto && !Builtins.arrayIterationChanged;

	public static function libTypedClass(cls:Dynamic, names:Array<String>, get:(JsObject, Int) -> Dynamic, set:(JsObject, Int, Dynamic) -> Void, alloc:JsObject->JsObject):Void {
		var f:JsFunction = cls;
		f.instanceLayout = new Layout(names, get, set);
		f.alloc = alloc;
	}

	// (a typed class: an instance for newTarget, made as Lib.construct does; its runtime Layout; its prototype locked)
	public static function libAllocate(newTarget:Dynamic):Dynamic return Lib.allocate(newTarget, Lib.protoFrom(newTarget, Builtins.ObjectProto));

	public static function libLayoutOf(cls:Dynamic):Dynamic return (cls : JsFunction).instanceLayout;

	public static function libLock(o:Dynamic):Void(o : JsObject).locked = true;

	public static function libDefineMethod(target:Dynamic, k:Dynamic, fn:Dynamic, kind:Int, enumerable:Bool):Void Lib.defineMethod(target, k, fn, kind, enumerable);

	public static function libDefineField(target:Dynamic, k:Dynamic, v:Dynamic):Void Lib.defineField(target, k, v);

	public static function libSetProto(o:Dynamic, p:Dynamic):Void Lib.setPrototype(o, p);

	public static function libCall(f:Dynamic, thisArg:Dynamic, args:Array<Dynamic>):Dynamic return Lib.call(f, thisArg, args);

	public static function libCallMethod(o:Dynamic, k:Dynamic, args:Array<Dynamic>):Dynamic return Lib.callMethod(o, k, args);

	public static function libConstruct(f:Dynamic, args:Array<Dynamic>, newTarget:Dynamic):Dynamic return Lib.construct(f, args, newTarget);

	public static function libSuperConstruct(cls:Dynamic, args:Array<Dynamic>, newTarget:Dynamic):Dynamic return Lib.superConstruct(cls, args, newTarget);

	public static function libConstructResult(r:Dynamic, self:Dynamic):Dynamic return Lib.isObject(r) ? r : self;

	public static function libSuperGet(home:Dynamic, self:Dynamic, k:Dynamic):Dynamic return Lib.superGet(home, self, k);

	public static function libSuperSet(home:Dynamic, self:Dynamic, k:Dynamic, v:Dynamic):Dynamic return Lib.superSet(home, self, k, v);

	public static function libSuperCall(home:Dynamic, self:Dynamic, k:Dynamic, args:Array<Dynamic>):Dynamic return Lib.call(Lib.superGet(home, self, k), self, args);

	public static function libPrivateGet(o:Dynamic, brand:String):Dynamic return Lib.privateGet(o, brand);

	public static function libPrivateSet(o:Dynamic, brand:String, v:Dynamic):Dynamic return Lib.privateSet(o, brand, v);

	public static function libPrivateDefine(o:Dynamic, brand:String, v:Dynamic, kind:Int):Void Lib.privateDefine(o, brand, v, kind);

	public static function libPrivateHas(o:Dynamic, brand:String):Bool return Lib.privateHas(o, brand);

	public static function libStep(it:Dynamic):Dynamic return Lib.step(it);

	public static function libRestArray(it:Dynamic):Dynamic return Lib.restArray(it);

	public static function libRequireObject(o:Dynamic):Void Lib.requireObject(o);

	public static function libObjectRest(o:Dynamic, used:Array<Dynamic>):Dynamic return Lib.objectRest(o, used);

	public static function libAssignSpread(o:Dynamic, source:Dynamic):Void Lib.assignSpread(o, source);

	public static function libAppend(list:Array<Dynamic>, v:Dynamic):Void list.push(v);

	public static function libAppendAll(list:Array<Dynamic>, source:Dynamic):Void Lib.appendAll(list, source);

	public static function libArray(values:Array<Dynamic>):Dynamic return Lib.array(values);

	public static function libObject(keys:Array<Dynamic>, values:Array<Dynamic>):Dynamic return Lib.object(keys, values);

	public static function libGet(o:Dynamic, k:Dynamic):Dynamic return Lib.get(o, k);

	public static function libPut(o:Dynamic, k:Dynamic, v:Dynamic):Dynamic return Lib.put(o, k, v);

	public static function libDelete(o:Dynamic, k:Dynamic):Bool return Lib.remove(o, k);

	public static function libHas(o:Dynamic, k:Dynamic):Bool return Lib.has(o, k);

	public static function libIterator(v:Dynamic):Dynamic return Lib.iterator(v);

	public static function libIterate(it:Dynamic):Dynamic return Lib.iterate(it);

	public static function libFinished(v:Dynamic):Bool return v == Lib.finished;

	public static function libInstanceOf(v:Dynamic, ctor:Dynamic):Bool return Lib.instanceOf(v, ctor);

	public static function libRelation(a:Dynamic, b:Dynamic, op:String):Bool return Lib.relation(a, b, op);

	public static function libInt(v:Dynamic):Int return Lib.toInt32(v);

	public static function libUnsigned(v:Int):Float return v < 0 ? v + 4294967296.0 : v;

	public static function libHole():Dynamic return Lib.hole;

	public static function libIsObject(v:Dynamic):Bool return Lib.isObject(v);

	public static function libGenerator(step:Dynamic):Dynamic return Async.generator(step);

	public static function libRunEventLoop():Void {
		Promises.runEventLoop();
		Builtins.checkAsyncTest();
	}

	public static function libRegExp(source:String, flags:String):Dynamic return Regex.compile(source, flags);

	public static function libModuleNamespace():Dynamic {
		var o = new JsObject(null);
		o.setOwn(Symbols.toStringTag, "Module", Attr.HIDDEN | Attr.READONLY | Attr.LOCKED);
		return o;
	}

	public static function libTemplateObject(cooked:Array<Dynamic>, raw:Array<Dynamic>):Dynamic return Builtins.templateObject(cooked, raw);

	public static function libAsync(step:Dynamic):Dynamic return Promises.async(step);

	public static function libSuspend(g:Dynamic, id:Int, kind:Int):Void Async.suspend(g, id, kind);

	public static function libAsyncGenerator(step:Dynamic):Dynamic return Promises.asyncGenerator(step);

	public static function libAsyncIterator(v:Dynamic):Dynamic return Promises.asyncIterator(v);

	public static function libResumePoint(g:Dynamic):Int {
		var gen:JsGenerator = g;
		return gen.suspended ? 0 : gen.state;
	}

	public static function libSave(g:Dynamic, locals:Array<Dynamic>):Void {
		var gen:JsGenerator = g;
		gen.frame = locals;
	}

	public static function libRestore(g:Dynamic, i:Int):Dynamic {
		var gen:JsGenerator = g;
		return gen.frame[i];
	}

	public static function libDelegate(it:Dynamic, received:Dynamic, mode:Dynamic):Dynamic return Async.delegate(it, received, mode);

	public static function libNamespaceGet(ns:Dynamic, name:String):Dynamic return Lib.hasOwnKey(ns, name) ? Lib.get(ns, name) : Builtins.global(name);

	public static function libList(v:Dynamic):Array<Dynamic> return Lib.toList(v);

	public static function libForInKeys(o:Dynamic):Dynamic return Lib.forInKeys(o);

	public static function main() {
		// Keep the semantics layer reachable during seed lowering. Reach prunes
		// this entry and helpers unused by the actual TypeScript program afterwards.
		libInit();
		libInstallRegExp();
		libInstallNormalize();
		libInstallDate();
		libInstallBuffers();
		libInstallJson();
		libInstallIteratorHelpers();
		libInstallPromise();
		libInstallFromAsync();
		libInstallSetMethods();
		libInstallUri();
		libInstallStructuredClone();
		libInstallAll();
		libTypeofGlobal("Object");
		libTypeofNamespace(libObject([], []), "x");
		var o = libObject([], []);
		var a = libArray([]);
		var f = libGlobal("Object");
		libFunction(() -> null, 0, false, 0, "");
		libClass("", libHole(), () -> null, 0, false, null);
		libTypedClass(f, [], (o, i) -> null, (o, i, v) -> {}, p -> p);
		mathSqrt(mathAbs(mathFloor(mathCeil(mathUnary("sin", mathBinary("atan2", mathMin(0, mathMax(0, 0)), 0))))));
		libArrayIterable(a);
		expectNumber(0, "");
		expectBoolean(true, "");
		expectString("", "");
		stringCharCodeAt("", 0);
		libBufferAdd(libBuffer(""), libBuffered(libBuffer("")));
		libLock(libAllocate(libLayoutOf(f)));
		diverge("", null, "");
		libDefineMethod(o, "x", f, 0, true);
		libDefineField(o, "x", null);
		libSetProto(o, null);
		libCall(f, null, []);
		libCallMethod(o, "x", []);
		libConstruct(f, [], f);
		libSuperConstruct(f, [], f);
		libConstructResult(o, o);
		libSuperGet(o, o, "x");
		libSuperSet(o, o, "x", null);
		libSuperCall(o, o, "x", []);
		libPrivateGet(o, "#x");
		libPrivateSet(o, "#x", null);
		libPrivateDefine(o, "#x", null, 0);
		libPrivateHas(o, "#x");
		libStep(libIterator(a));
		libRestArray(libIterator(a));
		libRequireObject(o);
		libObjectRest(o, []);
		libAssignSpread(o, null);
		libAppend([], null);
		libAppendAll([], a);
		libGet(o, "x");
		libPut(o, "x", null);
		libDelete(o, "x");
		libHas(o, "x");
		libIterate(libIterator(a));
		libFinished(null);
		libInstanceOf(null, f);
		uncaught(null);
		libList(a);
		libIsObject(a);
		var g = libGenerator(f);
		libSuspend(g, 1, 0);
		libAsyncGenerator(f);
		libAsyncIterator(a);
		libResumePoint(g);
		libSave(g, []);
		libRestore(g, 0);
		libDelegate(a, null, 0);
		libAsync(f);
		libRunEventLoop();
		libRegExp("a", "g");
		libModuleNamespace();
		libTemplateObject([], []);
		libNamespaceGet(o, "x");
		libForInKeys(o);
		libRelation(0, 1, "<");
		libInt(0);
		libUnsigned(0);
		libHole();
		print(consoleLine([]));
		print(numberText(modulo(1, 2)));
		print(numberText(power(1, 2)));
		print(consoleText(0));
		print(consoleNumber(0));
		print(text(getUndefined()));
		print(numberText(1));
		print(typeOf(null));
		print(text(truth(null)));
		print(text(strictEq(null, null)));
		print(text(looseEq(null, null)));
		print(text(numeric(null)));
		print(text(add(1, "a")));
		print(concat("", ""));
		print(text(stringEq("", "")));
		print(text(stringLength("")));
	}
}
