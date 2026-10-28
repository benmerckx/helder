package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Symbols.JsSymbol;

// The JavaScript object model: property access through prototype chains,
// calls and construction, classes, and conversions. Built-in objects are set
// up in Builtins. Host Haxe arrays are argument lists; JS arrays are JsArrays.
class Lib {
	public static var hole:Dynamic = new Hole();
	// (an own property lookup that found nothing)
	static var absent:Dynamic = new Hole();
	// (Lib.iterate: the iterator is done)
	public static var finished:Dynamic = new Hole();
	public static inline function undef():Dynamic return Seed.undefinedValue;

	public static function error(name:String, message:String):Dynamic throw Builtins.makeError(name, message);

	public static function isObject(v:Dynamic):Bool return Std.isOfType(v, JsObject);

	public static function isCallable(v:Dynamic):Bool return Std.isOfType(v, JsFunction) && (v : JsFunction).kind < JsFunction.BASE;

	public static function isConstructor(v:Dynamic):Bool {
		if (!Std.isOfType(v, JsFunction)) return false;
		var f:JsFunction = cast v;
		return f.kind != JsFunction.METHOD;
	}

	public static function isNumber(v:Dynamic):Bool return Std.isOfType(v, Float) || Std.isOfType(v, Int);

	public static function arg(args:Array<Dynamic>, i:Int):Dynamic return i < args.length ? args[i] : undef();

	public static function key(v:Dynamic):String {
		if (Std.isOfType(v, String)) return v;
		if (Std.isOfType(v, JsSymbol)) return (v : JsSymbol).key;
		if (isObject(v)) {
			v = toPrimitive(v, "string");
			if (Std.isOfType(v, JsSymbol)) return (v : JsSymbol).key;
		}
		return Seed.text(v);
	}

	public static function index(k:String):Float {
		if (k == "" || k.length > 10) return -1;
		var n = Std.parseFloat(k);
		return n >= 0 && n < 4294967295.0 && Math.ffloor(n) == n && Seed.numberText(n) == k ? n : -1;
	}

	// (an integral number usable as an array index, else -1)
	static inline function numericIndex(k:Dynamic):Float {
		var n:Float = k;
		return n >= 0 && n < 4294967295.0 && Math.ffloor(n) == n ? n : -1;
	}

	public static function describe(v:Dynamic):String {
		if (v == undef()) return "undefined";
		if (v == null) return "null";
		if (Std.isOfType(v, String)) return '"' + v + '"';
		if (Std.isOfType(v, JsFunction)) return (v : JsFunction).name == "" ? "function" : (v : JsFunction).name;
		if (isObject(v)) return "#<" + className(v) + ">";
		return Seed.text(v);
	}

	static function className(o:JsObject):String {
		var c = getKey(o, "constructor", o);
		return Std.isOfType(c, JsFunction) && (c : JsFunction).name != "" ? (c : JsFunction).name : "Object";
	}

	static function protoOf(v:Dynamic):JsObject {
		if (isObject(v)) return (v : JsObject).proto;
		if (Std.isOfType(v, String)) return Builtins.StringProto;
		if (Std.isOfType(v, Bool)) return Builtins.BooleanProto;
		if (Std.isOfType(v, JsSymbol)) return Builtins.SymbolProto;
		if (isNumber(v)) return Builtins.NumberProto;
		return null;
	}

	public static function protoFrom(newTarget:Dynamic, fallback:JsObject):JsObject {
		if (!isObject(newTarget)) return fallback;
		var p = get(newTarget, "prototype");
		return isObject(p) ? p : fallback;
	}

	// Properties.
	public static function get(o:Dynamic, k:Dynamic):Dynamic {
		if (o == null || o == undef()) return error("TypeError", "Cannot read properties of " + Seed.text(o) + " (reading '" + key(k) + "')");
		if (Std.isOfType(o, JsArray) && isNumber(k)) {
			var a:JsArray = cast o;
			var i = numericIndex(k);
			if (i >= 0 && i < a.items.length) {
				var v = a.items[Std.int(i)];
				if (v != hole) return v;
			}
		}
		return getKey(o, key(k), o);
	}

	public static function getKey(o:Dynamic, name:String, receiver:Dynamic):Dynamic {
		var obj:JsObject;
		if (isObject(o)) obj = o;
		else {
			if (Std.isOfType(o, String)) {
				var s:String = o;
				if (name == "length") return s.length;
				var i = index(name);
				if (i >= 0 && i < s.length) return s.charAt(Std.int(i));
			}
			obj = protoOf(o);
		}
		while (obj != null) {
			var v = ownGet(obj, name, receiver);
			if (v != absent) return v;
			obj = obj.proto;
		}
		return undef();
	}

	static function ownGet(obj:JsObject, name:String, receiver:Dynamic):Dynamic {
		if (Std.isOfType(obj, JsArray)) {
			var a:JsArray = cast obj;
			if (name == "length") return a.length;
			var i = index(name);
			if (i >= 0 && i < a.items.length) {
				var v = a.items[Std.int(i)];
				return v == hole ? absent : v;
			}
		}
		if (obj.hasOwn(name)) {
			var v = obj.getOwn(name);
			if (Std.isOfType(v, Accessor)) {
				var acc:Accessor = v;
				return acc.getter == null ? undef() : call(acc.getter, receiver, []);
			}
			return v;
		}
		if (Std.isOfType(obj, JsFunction)) return functionOwn(cast obj, name);
		return absent;
	}

	// (a function's name, length and lazily created prototype)
	static function functionOwn(f:JsFunction, name:String):Dynamic {
		if (f.deletedSpecial != null && f.deletedSpecial.exists(name)) return absent;
		return switch (name) {
			case "name": f.name;
			case "length": f.rest ? f.arity - 1 : f.arity;
			case "prototype" if (f.kind == JsFunction.PLAIN && f.native == null):
				var p = new JsObject(Builtins.ObjectProto);
				p.setOwn("constructor", f, Attr.HIDDEN);
				f.setOwn("prototype", p, Attr.HIDDEN | Attr.LOCKED);
				p;
			case _: absent;
		};
	}

	public static function hasOwnKey(o:Dynamic, name:String):Bool {
		if (Std.isOfType(o, String)) {
			var s:String = o;
			var i = index(name);
			return name == "length" || i >= 0 && i < s.length;
		}
		if (!isObject(o)) return false;
		var obj:JsObject = o;
		if (Std.isOfType(obj, JsArray)) {
			var a:JsArray = cast obj;
			if (name == "length") return true;
			var i = index(name);
			if (i >= 0 && i < a.items.length) return a.items[Std.int(i)] != hole;
		}
		if (obj.hasOwn(name)) return true;
		if (Std.isOfType(obj, JsFunction)) return functionOwn(cast obj, name) != absent;
		return false;
	}

	// The `in` operator.
	public static function has(o:Dynamic, k:Dynamic):Bool {
		if (!isObject(o)) return error("TypeError", "Cannot use 'in' operator to search for '" + key(k) + "' in " + Seed.text(o));
		var name = key(k);
		var obj:JsObject = o;
		while (obj != null) {
			if (hasOwnKey(obj, name)) return true;
			obj = obj.proto;
		}
		return false;
	}

	public static function put(o:Dynamic, k:Dynamic, v:Dynamic):Dynamic {
		if (o == null || o == undef()) return error("TypeError", "Cannot set properties of " + Seed.text(o) + " (setting '" + key(k) + "')");
		if (Std.isOfType(o, JsArray) && isNumber(k)) {
			var a:JsArray = cast o;
			var i = numericIndex(k);
			if (i >= 0 && i < a.items.length && a.items[Std.int(i)] != hole) {
				a.items[Std.int(i)] = v;
				return v;
			}
		}
		setKey(o, key(k), v, o);
		return v;
	}

	static function setKey(o:Dynamic, name:String, v:Dynamic, receiver:Dynamic):Void {
		if (!isObject(o)) {
			// (a primitive: only an inherited setter can accept the write)
			var acc = findAccessor(protoOf(o), name);
			if (acc != null && acc.setter != null) {
				call(acc.setter, receiver, [v]);
				return;
			}
			error("TypeError", "Cannot create property '" + name + "' on " + Seed.typeOf(o) + " '" + Seed.text(o) + "'");
			return;
		}
		var obj:JsObject = o;
		if (Std.isOfType(obj, JsArray)) {
			var a:JsArray = cast obj;
			if (name == "length") {
				setLength(a, v);
				return;
			}
			var i = index(name);
			if (i >= 0 && !obj.hasOwn(name) && inherited(obj.proto, name) == null) {
				setIndex(a, i, v);
				return;
			}
		}
		if (obj.hasOwn(name)) {
			var current = obj.getOwn(name);
			if (Std.isOfType(current, Accessor)) {
				var acc:Accessor = current;
				if (acc.setter == null) readOnly(name, obj);
				call(acc.setter, receiver, [v]);
				return;
			}
			if (obj.attr(name) & Attr.READONLY != 0) {
				readOnly(name, obj);
				return;
			}
			obj.writeOwn(name, v);
			return;
		}
		if (Std.isOfType(obj, JsFunction) && functionOwn(cast obj, name) != absent && name != "prototype") {
			readOnly(name, obj);
			return;
		}
		var found = inherited(obj.proto, name);
		if (found != null) {
			if (Std.isOfType(found, Accessor)) {
				var acc:Accessor = found;
				if (acc.setter == null) {
					readOnly(name, obj);
					return;
				}
				call(acc.setter, receiver, [v]);
				return;
			}
			readOnly(name, obj);
			return;
		}
		if (!obj.extensible) {
			error("TypeError", "Cannot add property " + name + ", object is not extensible");
			return;
		}
		obj.setOwn(name, v);
	}

	static function readOnly(name:String, obj:JsObject):Void error("TypeError", "Cannot assign to read only property '" + name + "' of " + (Std.isOfType(obj, JsFunction) ? "function" : "object") + " '" + describe(obj) + "'");

	// (an inherited accessor or read-only data property that governs a write; null when a plain write may proceed)
	static function inherited(obj:JsObject, name:String):Dynamic {
		while (obj != null) {
			if (obj.hasOwn(name)) {
				var v = obj.getOwn(name);
				if (Std.isOfType(v, Accessor)) return v;
				return obj.attr(name) & Attr.READONLY != 0 ? v : null;
			}
			obj = obj.proto;
		}
		return null;
	}

	static function findAccessor(obj:JsObject, name:String):Accessor {
		while (obj != null) {
			if (obj.hasOwn(name)) {
				var v = obj.getOwn(name);
				return Std.isOfType(v, Accessor) ? v : null;
			}
			obj = obj.proto;
		}
		return null;
	}

	public static function setIndex(a:JsArray, i:Float, v:Dynamic):Void {
		var n = a.items.length;
		if (i < n) {
			a.items[Std.int(i)] = v;
		}
		else if (i < n * 2 + 64 && i < 16777216) {
			var name = Seed.numberText(i);
			if (a.hasOwn(name)) a.removeOwn(name);
			while (a.items.length < i) a.items.push(hole);
			a.items.push(v);
		}
		else a.setOwn(Seed.numberText(i), v);
		if (i >= a.length) a.length = i + 1;
	}

	public static function setLength(a:JsArray, v:Dynamic):Void {
		var len = Seed.numeric(v);
		if (Math.isNaN(len) || len < 0 || len > 4294967295.0 || Math.ffloor(len) != len) {
			error("RangeError", "Invalid array length");
			return;
		}
		if (len < a.items.length) a.items.resize(Std.int(len));
		if (a.names != null) for (n in a.names.copy()) if (index(n) >= len) a.removeOwn(n);
		a.length = len;
	}

	public static function remove(o:Dynamic, k:Dynamic):Bool {
		if (o == null || o == undef()) return error("TypeError", "Cannot convert undefined or null to object");
		if (!isObject(o)) return true;
		var obj:JsObject = o;
		var name = key(k);
		if (Std.isOfType(obj, JsArray)) {
			var a:JsArray = cast obj;
			var i = index(name);
			if (i >= 0 && i < a.items.length) {
				a.items[Std.int(i)] = hole;
				return true;
			}
			if (name == "length") return error("TypeError", "Cannot delete property 'length' of [object Array]");
		}
		if (obj.attr(name) & Attr.LOCKED != 0) return error("TypeError", "Cannot delete property '" + name + "' of " + describe(obj));
		if (Std.isOfType(obj, JsFunction) && (name == "name" || name == "length")) {
			var f:JsFunction = cast obj;
			if (f.deletedSpecial == null) f.deletedSpecial = [];
			f.deletedSpecial.set(name, true);
		}
		obj.removeOwn(name);
		return true;
	}

	// Own string keys: integer indices ascending, then others in insertion order.
	public static function ownKeys(o:Dynamic, enumerableOnly:Bool):Array<String> {
		if (o == null || o == undef()) return error("TypeError", "Cannot convert undefined or null to object");
		if (Std.isOfType(o, String)) {
			var s:String = o;
			return [for (i in 0...s.length) Std.string(i)];
		}
		if (!isObject(o)) return [];
		var obj:JsObject = o;
		var out:Array<String> = [];
		if (Std.isOfType(obj, JsArray)) {
			var a:JsArray = cast obj;
			for (i in 0...a.items.length) if (a.items[i] != hole) out.push(Std.string(i));
		}
		var own = obj.ownNames();
		if (own == null) return out;
		var numeric:Array<String> = [];
		var other:Array<String> = [];
		for (n in own) {
			if (enumerableOnly && obj.attr(n) & Attr.HIDDEN != 0) continue;
			if (Symbols.isSymbolKey(n)) continue;
			if (index(n) >= 0) numeric.push(n); else other.push(n);
		}
		numeric.sort((x, y) -> {
			var a = index(x), b = index(y);
			return a < b ? -1 : a > b ? 1 : 0;});
		return out.concat(numeric).concat(other);
	}

	public static function keys(o:Dynamic):Array<String> return ownKeys(o, true);

	public static function defineOwn(o:JsObject, name:String, v:Dynamic, attribute:Int = 0):Void {
		if (Std.isOfType(o, JsArray)) {
			var i = index(name);
			if (i >= 0 && attribute == 0) {
				setIndex(cast o, i, v);
				return;
			}
		}
		o.setOwn(name, v, attribute);
	}

	// Calls and construction.
	static function positional(f:JsFunction, args:Array<Dynamic>):Array<Dynamic> {
		var fixed = f.rest ? f.arity - 1 : f.arity;
		var passed = args.length == fixed ? args.copy() : args.slice(0, fixed);
		while (passed.length < fixed) passed.push(undef());
		if (f.rest) passed.push(array(args.slice(fixed)));
		return passed;
	}

	public static function call(f:Dynamic, thisArg:Dynamic, args:Array<Dynamic>):Dynamic {
		if (!Std.isOfType(f, JsFunction)) return error("TypeError", describe(f) + " is not a function");
		var fn:JsFunction = f;
		if (fn.native != null) return fn.native(thisArg, args, undef());
		if (fn.kind >= JsFunction.BASE) return error("TypeError", "Class constructor " + fn.name + " cannot be invoked without 'new'");
		var passed = positional(fn, args);
		passed.unshift(thisArg);
		return Reflect.callMethod(null, fn.impl, passed);
	}

	public static function callMethod(o:Dynamic, k:Dynamic, args:Array<Dynamic>):Dynamic {
		var f = get(o, k);
		if (!Std.isOfType(f, JsFunction)) return error("TypeError", (isObject(o) ? describe(o) : Seed.typeOf(o)) + "." + key(k) + " is not a function");
		return call(f, o, args);
	}

	public static function construct(f:Dynamic, args:Array<Dynamic>, newTarget:Dynamic):Dynamic {
		if (!isConstructor(f)) return error("TypeError", describe(f) + " is not a constructor");
		if (!isConstructor(newTarget)) return error("TypeError", "newTarget is not a constructor");
		var fn:JsFunction = f;
		if (fn.native != null) return fn.native(undef(), args, newTarget);
		var passed = positional(fn, args);
		switch (fn.kind) {
			case JsFunction.PLAIN:
				var obj = new JsObject(protoFrom(newTarget, Builtins.ObjectProto));
				passed.unshift(obj);
				var r = Reflect.callMethod(null, fn.impl, passed);
				return isObject(r) ? r : obj;
			case JsFunction.BASE:
				var obj = new JsObject(protoFrom(newTarget, Builtins.ObjectProto));
				initFields(fn, obj);
				passed.unshift(newTarget);
				passed.unshift(obj);
				var r = Reflect.callMethod(null, fn.impl, passed);
				return isObject(r) ? r : obj;
			case _:
				passed.unshift(newTarget);
				passed.unshift(undef());
				var r = Reflect.callMethod(null, fn.impl, passed);
				if (!isObject(r)) return error("ReferenceError", "Must call super constructor in derived class before accessing 'this' or returning from derived constructor");
				return r;
		}
	}

	// super(...) in a derived class constructor: the parent builds `this`, then this class's fields are set.
	public static function superConstruct(cls:Dynamic, args:Array<Dynamic>, newTarget:Dynamic):Dynamic {
		var fn:JsFunction = cls;
		if (!isConstructor(fn.parent)) return error("TypeError", "Super constructor " + Seed.text(fn.parent) + " of anonymous class is not a constructor");
		var obj = construct(fn.parent, args, newTarget);
		initFields(fn, obj);
		return obj;
	}

	static function initFields(fn:JsFunction, obj:Dynamic):Void if (fn.fields != null) Reflect.callMethod(null, fn.fields, [obj]);

	// A compiled function or arrow (kind METHOD) as a value.
	public static function makeFunction(impl:Dynamic, arity:Int, rest:Bool, kind:Int, name:String):Dynamic {
		var f = new JsFunction(Builtins.FunctionProto, kind, name, arity);
		f.impl = impl;
		f.rest = rest;
		return f;
	}

	// A class: its constructor function and prototype object. parent is hole without extends.
	public static function makeClass(name:String, parent:Dynamic, impl:Dynamic, arity:Int, rest:Bool, fields:Dynamic):Dynamic {
		var derived = parent != hole;
		var protoParent = Builtins.ObjectProto;
		var ctorProto = Builtins.FunctionProto;
		if (derived) {
			if (parent == null) protoParent = null;
			else {
				if (!isConstructor(parent)) return error("TypeError", "Class extends value " + describe(parent) + " is not a constructor or null");
				var pp = get(parent, "prototype");
				if (pp != null && !isObject(pp)) return error("TypeError", "Class extends value does not have valid prototype property " + Seed.text(pp));
				protoParent = pp;
				ctorProto = parent;
			}
		}
		var c = new JsFunction(ctorProto, derived ? JsFunction.DERIVED : JsFunction.BASE, name, arity);
		c.impl = impl;
		c.rest = rest;
		c.fields = fields;
		c.parent = derived ? parent : null;
		var proto = new JsObject(protoParent);
		proto.setOwn("constructor", c, Attr.HIDDEN);
		c.setOwn("prototype", proto, Attr.HIDDEN | Attr.READONLY | Attr.LOCKED);
		return c;
	}

	// Methods (kind 0), getters (1) and setters (2) on a prototype, class or object literal.
	public static function defineMethod(target:Dynamic, k:Dynamic, fn:Dynamic, kind:Int, enumerable:Bool):Void {
		var obj:JsObject = target;
		var name = key(k);
		var attribute = enumerable ? 0 : Attr.HIDDEN;
		if (Std.isOfType(fn, JsFunction)) {
			var f:JsFunction = fn;
			f.name = (kind == 1 ? "get " : kind == 2 ? "set " : "") + Symbols.functionName(name);
		}
		if (kind == 0) {
			obj.setOwn(name, fn, attribute);
			return;
		}
		var current = obj.hasOwn(name) ? obj.getOwn(name) : null;
		var acc = Std.isOfType(current, Accessor) ? (current : Accessor) : new Accessor(null, null);
		if (kind == 1) acc.getter = fn; else acc.setter = fn;
		obj.setOwn(name, acc, attribute);
	}

	// Class fields and object literal properties: own data properties, defined (setters are not called).
	public static function defineField(target:Dynamic, k:Dynamic, v:Dynamic):Void {
		var obj:JsObject = target;
		var name = key(k);
		if (Std.isOfType(v, JsFunction) && (v : JsFunction).name == "" && (v : JsFunction).native == null) (v : JsFunction).name = Symbols.functionName(name);
		defineOwn(obj, name, v);
	}

	public static function setPrototype(o:Dynamic, proto:Dynamic):Void {
		if (isObject(o) && (proto == null || isObject(proto))) (o : JsObject).proto = proto;
	}

	// Private class elements, keyed by brand.
	public static function privateGet(o:Dynamic, brand:String):Dynamic {
		var obj:JsObject = isObject(o) ? o : null;
		if (obj == null || obj.privates == null || !obj.privates.exists(brand)) return error("TypeError", "Cannot read private member " + brand.split("@")[0] + " from an object whose class did not declare it");
		var v = obj.privates.get(brand);
		if (Std.isOfType(v, Accessor)) {
			var acc:Accessor = v;
			return acc.getter == null ? error("TypeError", "'" + brand.split("@")[0] + "' was defined without a getter") : call(acc.getter, o, []);
		}
		return v;
	}

	public static function privateSet(o:Dynamic, brand:String, v:Dynamic):Dynamic {
		var obj:JsObject = isObject(o) ? o : null;
		if (obj == null || obj.privates == null || !obj.privates.exists(brand)) return error("TypeError", "Cannot write private member " + brand.split("@")[0] + " to an object whose class did not declare it");
		var current = obj.privates.get(brand);
		if (Std.isOfType(current, Accessor)) {
			var acc:Accessor = current;
			if (acc.setter == null) return error("TypeError", "'" + brand.split("@")[0] + "' was defined without a setter");
			call(acc.setter, o, [v]);
			return v;
		}
		if (Std.isOfType(current, JsFunction) && obj.privates.exists(brand + "@method")) return error("TypeError", "Private method is not writable");
		obj.privates.set(brand, v);
		return v;
	}

	public static function privateDefine(o:Dynamic, brand:String, v:Dynamic, kind:Int):Void {
		var obj:JsObject = o;
		if (obj.privates == null) obj.privates = [];
		if (kind == 0) {
			if (obj.privates.exists(brand)) error("TypeError", "Cannot initialize " + brand.split("@")[0] + " twice on the same object");
			obj.privates.set(brand, v);
			return;
		}
		if (kind == 3) {
			obj.privates.set(brand, v);
			obj.privates.set(brand + "@method", true);
			return;
		}
		var current = obj.privates.get(brand);
		var acc = Std.isOfType(current, Accessor) ? (current : Accessor) : new Accessor(null, null);
		if (kind == 1) acc.getter = v; else acc.setter = v;
		obj.privates.set(brand, acc);
	}

	public static function privateHas(o:Dynamic, brand:String):Bool {
		if (!isObject(o)) return error("TypeError", "Cannot use 'in' operator to search for '" + brand.split("@")[0] + "' in " + Seed.text(o));
		var obj:JsObject = o;
		return obj.privates != null && obj.privates.exists(brand);
	}

	// super.x and super.m(...): lookups start above the method's home object.
	public static function superGet(home:Dynamic, thisArg:Dynamic, k:Dynamic):Dynamic {
		var h:JsObject = home;
		return h.proto == null ? undef() : getKey(h.proto, key(k), thisArg);
	}

	public static function superSet(home:Dynamic, thisArg:Dynamic, k:Dynamic, v:Dynamic):Dynamic {
		var h:JsObject = home;
		var name = key(k);
		var acc = findAccessor(h.proto, name);
		if (acc != null) {
			if (acc.setter != null) call(acc.setter, thisArg, [v]);
			return v;
		}
		setKey(thisArg, name, v, thisArg);
		return v;
	}

	public static function instanceOf(v:Dynamic, c:Dynamic):Bool {
		if (!isObject(c)) return error("TypeError", "Right-hand side of 'instanceof' is not " + (isObject(c) ? "callable" : "an object"));
		var custom = getKey(c, Symbols.hasInstance, c);
		if (custom != undef() && custom != null) return Seed.truth(call(custom, c, [v]));
		if (!Std.isOfType(c, JsFunction)) return error("TypeError", "Right-hand side of 'instanceof' is not callable");
		var f:JsFunction = c;
		if (f.native != null && f.hasOwn(Builtins.boundTarget)) return instanceOf(v, f.getOwn(Builtins.boundTarget));
		if (!isObject(v)) return false;
		var p = get(c, "prototype");
		if (!isObject(p)) return error("TypeError", "Function has non-object prototype '" + Seed.text(p) + "' in instanceof check");
		var o:JsObject = (v : JsObject).proto;
		while (o != null) {
			if (o == p) return true;
			o = o.proto;
		}
		return false;
	}

	// Conversions.
	public static function toPrimitive(o:Dynamic, hint:String):Dynamic {
		if (!isObject(o)) return o;
		var exotic = getKey(o, Symbols.toPrimitive, o);
		if (exotic != undef() && exotic != null) {
			var r = call(exotic, o, [hint]);
			if (!isObject(r)) return r;
			return error("TypeError", "Cannot convert object to primitive value");
		}
		var order = hint == "string" ? ["toString", "valueOf"] : ["valueOf", "toString"];
		for (m in order) {
			var f = getKey(o, m, o);
			if (isCallable(f)) {
				var r = call(f, o, []);
				if (!isObject(r)) return r;
			}
		}
		return error("TypeError", "Cannot convert object to primitive value");
	}

	public static function toObject(v:Dynamic):JsObject {
		if (v == null || v == undef()) return error("TypeError", "Cannot convert undefined or null to object");
		return isObject(v) ? v : Builtins.wrap(v);
	}

	// Arrays, objects and iteration.
	public static function array(items:Array<Dynamic>):Dynamic {
		var a = new JsArray(Builtins.ArrayProto);
		a.items = items;
		a.length = items.length;
		return a;
	}

	public static function object(keys:Array<Dynamic>, values:Array<Dynamic>):Dynamic {
		var o = new JsObject(Builtins.ObjectProto);
		for (i in 0...keys.length) defineOwn(o, key(keys[i]), values[i]);
		return o;
	}

	public static function iterator(o:Dynamic):Dynamic {
		var method = o == null || o == undef() ? undef() : getKey(o, Symbols.iterator, o);
		if (!isCallable(method)) return error("TypeError", (isObject(o) ? "object" : Seed.text(o)) + " is not iterable");
		var it = call(method, o, []);
		if (!isObject(it)) return error("TypeError", "Result of the Symbol.iterator method is not an object");
		return it;
	}

	public static function next(it:Dynamic):Dynamic {
		if (Std.isOfType(it, JsIterator)) return Builtins.iteratorNext(it);
		var r = callMethod(it, "next", []);
		if (!isObject(r)) return error("TypeError", "Iterator result " + Seed.text(r) + " is not an object");
		return r;
	}

	// The next value of an iterator, or `finished`.
	public static function iterate(it:Dynamic):Dynamic {
		if (Std.isOfType(it, JsIterator)) {
			var i:JsIterator = it;
			if (i.finished) return finished;
			var v = Builtins.iteratorStep(i);
			if (v == finished) i.finished = true;
			return v;
		}
		var r = next(it);
		return Seed.truth(get(r, "done")) ? finished : get(r, "value");
	}

	// Destructuring: the next value (undefined once done), and the rest as an array.
	public static function step(it:Dynamic):Dynamic {
		var v = iterate(it);
		return v == finished ? undef() : v;
	}

	public static function restArray(it:Dynamic):Dynamic {
		var values = [];
		while (true) {
			var v = iterate(it);
			if (v == finished) break;
			values.push(v);
		}
		return array(values);
	}

	public static function toList(o:Dynamic):Array<Dynamic> {
		if (Std.isOfType(o, JsArray) && (o : JsArray).proto == Builtins.ArrayProto && !Builtins.arrayIterationChanged) {
			var a:JsArray = cast o;
			var out = [for (v in a.items) v == hole ? undef() : v];
			while (out.length < a.length) out.push(get(a, out.length));
			return out;
		}
		var it = iterator(o);
		var values = [];
		while (true) {
			var v = iterate(it);
			if (v == finished) break;
			values.push(v);
		}
		return values;
	}

	// for-in: enumerable string keys of the object and its prototypes, each once.
	public static function forInKeys(o:Dynamic):Dynamic {
		if (o == null || o == undef()) return array([]);
		var obj = toObject(o);
		var seen:Map<String, Bool> = [];
		var out:Array<Dynamic> = [];
		while (obj != null) {
			for (k in Builtins.ownPropertyKeys(obj)) {
				if (Symbols.isSymbolKey(k) || seen.exists(k)) continue;
				seen.set(k, true);
				if (obj.attr(k) & Attr.HIDDEN == 0 && hasOwnKey(obj, k) && !(Std.isOfType(obj, JsArray) && k == "length") && !(Std.isOfType(obj, JsFunction) && !obj.hasOwn(k))) out.push(k);
			}
			obj = obj.proto;
		}
		return array(out);
	}

	public static function requireObject(o:Dynamic):Void if (o == null || o == undef()) error("TypeError", "Cannot destructure '" + Seed.text(o) + "' as it is " + Seed.text(o) + ".");

	public static function objectRest(o:Dynamic, used:Array<Dynamic>):Dynamic {
		var excluded = [for (k in used) key(k)];
		var r = new JsObject(Builtins.ObjectProto);
		for (k in keys(o)) if (excluded.indexOf(k) < 0) r.setOwn(k, get(o, k));
		return r;
	}

	// (object spread: own enumerable properties; null and undefined add nothing)
	public static function assignSpread(target:Dynamic, source:Dynamic):Void {
		if (source == null || source == undef()) return;
		for (k in keys(source)) defineOwn(target, k, get(source, k));
	}

	public static function appendAll(list:Array<Dynamic>, source:Dynamic):Void for (v in toList(source)) list.push(v);

	public static function relation(a:Dynamic, b:Dynamic, op:String):Bool {
		a = toPrimitive(a, "number");
		b = toPrimitive(b, "number");
		if (Std.isOfType(a, String) && Std.isOfType(b, String)) {
			var c = compareStrings(a, b);
			return op == "<" ? c < 0 : op == "<=" ? c <= 0 : op == ">" ? c > 0 : c >= 0;
		}
		var x = Seed.numeric(a), y = Seed.numeric(b);
		return op == "<" ? x < y : op == "<=" ? x <= y : op == ">" ? x > y : x >= y;
	}

	public static function compareStrings(a:String, b:String):Int {
		var n = Std.int(Math.min(a.length, b.length));
		for (i in 0...n) {
			var x = a.charCodeAt(i), y = b.charCodeAt(i);
			if (x < y) return -1;
			if (x > y) return 1;
		}
		return a.length < b.length ? -1 : a.length > b.length ? 1 : 0;
	}

	public static function toIntegerOrInfinity(v:Dynamic):Float {
		var n = Seed.numeric(v);
		return Math.isNaN(n) || n == 0 ? 0 : !Math.isFinite(n) ? n : n < 0 ? Math.fceil(n) : Math.ffloor(n);
	}

	public static function toUint32(v:Dynamic):Float {
		var n = toIntegerOrInfinity(v);
		if (!Math.isFinite(n)) return 0;
		n = n % 4294967296.0;
		return n < 0 ? n + 4294967296.0 : n;
	}

	public static function toInt32(v:Dynamic):Int {
		var n = toUint32(v);
		return Std.int(n >= 2147483648.0 ? n - 4294967296.0 : n);
	}

	public static function sameValueZero(a:Dynamic, b:Dynamic):Bool return Seed.strictEq(a, b) || isNumber(a) && isNumber(b) && Math.isNaN(a) && Math.isNaN(b);

	public static function sameValue(a:Dynamic, b:Dynamic):Bool {
		if (isNumber(a) && isNumber(b)) {
			var x:Float = a, y:Float = b;
			if (Math.isNaN(x)) return Math.isNaN(y);
			if (x == 0 && y == 0) return 1 / x == 1 / y;
			return x == y;
		}
		return Seed.strictEq(a, b);
	}
}
