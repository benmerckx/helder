package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Symbols.JsSymbol;
import helder.typescript.js.Lib.*;
import helder.typescript.js.Builtins.*;
import helder.typescript.js.Arrays.*;
import helder.typescript.js.Strings.*;
import helder.typescript.js.Collections.*;
import helder.typescript.js.Globals.*;

// Object's built-ins: Object and its prototype, property descriptors and integrity, the primitives' wrappers.
@:access(helder.typescript.js.Builtins)
@:access(helder.typescript.js.Arrays)
@:access(helder.typescript.js.Strings)
@:access(helder.typescript.js.Collections)
@:access(helder.typescript.js.Globals)
class Objects {
	// Object
	static function setupObject():Void {
		var o = ObjectProto;
		method(o, "hasOwnProperty", 1, (t, a, _) -> hasOwnKey(toObject(t), key(arg(a, 0))));
		method(o, "isPrototypeOf", 1, (t, a, _) -> {
			var v = arg(a, 0);
			if (!isObject(v)) return false;
			var p = (v : JsObject).proto;
			while (p != null) {
				if (p == t) return true;
				p = p.proto;
			}
			return false;});
		method(o, "propertyIsEnumerable", 1, (t, a, _) -> {
			var obj = toObject(t);
			var k = key(arg(a, 0));
			return hasOwnKey(obj, k) && obj.attr(k) & Attr.HIDDEN == 0;});
		method(o, "toString", 0, (t, _, _) -> objectToString(t));
		method(o, "toLocaleString", 0, (t, _, _) -> callMethod(t, "toString", []));
		method(o, "valueOf", 0, (t, _, _) -> toObject(t));
		o.setOwn("__proto__", new Accessor(native("get __proto__", 0, (t, _, _) -> {
			var p = toObject(t).proto;
			return p;}), native("set __proto__", 1, (t, a, _) -> {
				setPrototype(t, arg(a, 0));
				return undef();})), Attr.HIDDEN);
		var c = constructor("Object", 1, o, (t, a, nt) -> {
			var v = arg(a, 0);
			return v == null || v == undef() ? new JsObject(ObjectProto) : toObject(v);});
		method(c, "keys", 1, (_, a, _) -> array([for (k in keys(toObject(arg(a, 0)))) k]));
		method(c, "values", 1, (_, a, _) -> {
			var o = toObject(arg(a, 0));
			return array([for (k in keys(o)) get(o, k)]);});
		method(c, "entries", 1, (_, a, _) -> {
			var o = toObject(arg(a, 0));
			return array([for (k in keys(o)) array([k, get(o, k)])]);});
		method(c, "assign", 2, (_, a, _) -> {
			var target = toObject(arg(a, 0));
			for (source in a.slice(1)) if (source != null && source != undef()) {
				var s = toObject(source);
				for (k in ownPropertyKeys(s)) if (enumerableOwn(s, k)) put(target, k, get(s, k));
			}
			return target;});
		method(c, "fromEntries", 1, (_, a, _) -> {
			var o = new JsObject(ObjectProto);
			for (entry in toList(arg(a, 0))) defineOwn(o, key(get(entry, 0)), get(entry, 1));
			return o;});
		method(c, "hasOwn", 2, (_, a, _) -> hasOwnKey(toObject(arg(a, 0)), key(arg(a, 1))));
		method(c, "is", 2, (_, a, _) -> sameValue(arg(a, 0), arg(a, 1)));
		method(c, "getPrototypeOf", 1, (_, a, _) -> toObject(arg(a, 0)).proto);
		method(c, "setPrototypeOf", 2, (_, a, _) -> {
			var o = arg(a, 0);
			var p = arg(a, 1);
			if (p != null && !isObject(p)) error("TypeError", "Object prototype may only be an Object or null: " + Seed.text(p));
			setPrototype(o, p);
			return o;});
		method(c, "create", 2, (_, a, _) -> {
			var p = arg(a, 0);
			if (p != null && !isObject(p)) error("TypeError", "Object prototype may only be an Object or null: " + Seed.text(p));
			var o = new JsObject(p);
			if (arg(a, 1) != undef()) defineProperties(o, arg(a, 1));
			return o;});
		method(c, "defineProperty", 3, (_, a, _) -> {
			var o = arg(a, 0);
			if (!isObject(o)) error("TypeError", "Object.defineProperty called on non-object");
			defineProperty(o, key(arg(a, 1)), arg(a, 2));
			return o;});
		method(c, "defineProperties", 2, (_, a, _) -> {
			var o = arg(a, 0);
			if (!isObject(o)) error("TypeError", "Object.defineProperties called on non-object");
			defineProperties(o, arg(a, 1));
			return o;});
		method(c, "getOwnPropertyNames", 1, (_, a, _) -> {
			var o = toObject(arg(a, 0));
			var names:Array<Dynamic> = [for (k in ownPropertyKeys(o)) if (!Symbols.isSymbolKey(k)) k];
			return array(names);});
		method(c, "getOwnPropertySymbols", 1, (_, a, _) -> {
			var o = toObject(arg(a, 0));
			var symbols:Array<Dynamic> = [for (k in ownPropertyKeys(o)) if (Symbols.isSymbolKey(k) && Symbols.fromKey(k) != null) Symbols.fromKey(k)];
			return array(symbols);});
		method(c, "getOwnPropertyDescriptor", 2, (_, a, _) -> descriptor(toObject(arg(a, 0)), key(arg(a, 1))));
		method(c, "getOwnPropertyDescriptors", 1, (_, a, _) -> {
			var o = toObject(arg(a, 0));
			var r = new JsObject(ObjectProto);
			for (k in ownPropertyKeys(o)) r.setOwn(k, descriptor(o, k));
			return r;});
		method(c, "freeze", 1, (_, a, _) -> {
			integrity(arg(a, 0), true);
			return arg(a, 0);});
		method(c, "seal", 1, (_, a, _) -> {
			integrity(arg(a, 0), false);
			return arg(a, 0);});
		method(c, "preventExtensions", 1, (_, a, _) -> {
			if (isObject(arg(a, 0))) (arg(a, 0) : JsObject).extensible = false;
			return arg(a, 0);});
		method(c, "isFrozen", 1, (_, a, _) -> testIntegrity(arg(a, 0), true));
		method(c, "isSealed", 1, (_, a, _) -> testIntegrity(arg(a, 0), false));
		method(c, "isExtensible", 1, (_, a, _) -> isObject(arg(a, 0)) && (arg(a, 0) : JsObject).extensible);
		method(c, "groupBy", 2, (_, a, _) -> groupBy(arg(a, 0), arg(a, 1), false));
	}

	// GroupBy consumes one iterator value per callback and caches the next method.
	// Only callback/key failures close the iterator; iterator-step failures do not.
	static function groupBy(items:Dynamic, fn:Dynamic, isMap:Bool):Dynamic {
		if (items == null || items == undef()) return error("TypeError", "Grouping requires an iterable");
		var f = callback(fn), it = iterator(items), nextFn = get(it, "next");
		var result:JsObject = isMap ? new JsMap(MapProto, false) : new JsObject(null);
		var i:Float = 0;
		while (true) {
			if (i >= 9007199254740991.0) return groupCloseThrow(it, makeError("TypeError", "Too many grouped values"));
			var step = call(nextFn, it, []);
			if (!isObject(step)) return error("TypeError", "Iterator result must be an object");
			if (Seed.truth(get(step, "done"))) return result;
			var value = get(step, "value"), k:Dynamic;
			try {
				k = call(f, undef(), [value, i]);
				if (!isMap) k = key(k);
			}
			catch (e:Dynamic) return groupCloseThrow(it, e);
			var list:JsArray;
			if (isMap) {
				var map:JsMap = cast result;
				var j = mapIndex(map, k);
				if (j < 0) {
					mapPut(map, k, array([]));
					j = mapIndex(map, k);
				}
				list = map.values[j];
			} else {
				var name:String = k;
				if (!result.hasOwn(name)) result.setOwn(name, array([]));
				list = result.getOwn(name);
			}
			setIndex(list, list.length, value);
			i++;
		}
	}

	static function groupCloseThrow(it:Dynamic, reason:Dynamic):Dynamic {
		// The original throw wins over failures getting or calling return().
		try {
			var ret = get(it, "return");
			if (ret != null && ret != undef()) call(ret, it, []);
		}
		catch (_:Dynamic) {}
		throw reason;
	}

	public static function objectToString(t:Dynamic):String {
		if (t == undef()) return "[object Undefined]";
		if (t == null) return "[object Null]";
		var o = toObject(t);
		var tag = getKey(o, Symbols.toStringTag, o);
		if (Std.isOfType(tag, String)) return "[object " + tag + "]";
		if (o.hasOwn("\x00@primitive")) {
			var p = o.getOwn("\x00@primitive");
			return "[object " + (Std.isOfType(p, String) ? "String" : Std.isOfType(p, Bool) ? "Boolean" : "Number") + "]";
		}
		var t = o.tag();
		return "[object " + (t == "Map" || t == "Set" ? "Object" : t) + "]";
	}

	static function enumerableOwn(o:JsObject, k:String):Bool return o.attr(k) & Attr.HIDDEN == 0;

	// All own keys (strings in order, then symbols), hidden ones included.
	public static function ownPropertyKeys(o:JsObject):Array<String> {
		var strings:Array<String> = [];
		var symbols:Array<String> = [];
		if (Std.isOfType(o, JsArray)) {
			var a:JsArray = cast o;
			for (i in 0...a.items.length) if (a.items[i] != hole) strings.push(Std.string(i));
		}
		var numeric:Array<String> = [];
		var other:Array<String> = [];
		if (o.ownNames() != null) for (n in o.ownNames()) if (Symbols.isSymbolKey(n)) symbols.push(n); else if (index(n) >= 0) numeric.push(n); else other.push(n);
		numeric.sort((x, y) -> {
			var a = index(x), b = index(y);
			return a < b ? -1 : a > b ? 1 : 0;});
		var extra:Array<String> = [];
		if (Std.isOfType(o, JsArray)) extra.push("length");
		if (Std.isOfType(o, JsFunction)) {
			for (k in ["length", "name"]) if (!o.hasOwn(k) && hasOwnKey(o, k)) extra.push(k);
		}
		return strings.concat(numeric).concat(extra).concat(other).concat(symbols);
	}

	static function descriptor(o:JsObject, k:String):Dynamic {
		if (!hasOwnKey(o, k)) return undef();
		var d = new JsObject(ObjectProto);
		var attribute = o.attr(k);
		var v:Dynamic = o.hasOwn(k) ? o.getOwn(k) : get(o, k);
		var virtual = !o.hasOwn(k);
		if (Std.isOfType(v, Accessor)) {
			var acc:Accessor = v;
			d.setOwn("get", acc.getter == null ? undef() : acc.getter);
			d.setOwn("set", acc.setter == null ? undef() : acc.setter);
		}
		else {
			d.setOwn("value", v);
			d.setOwn("writable", virtual ? (Std.isOfType(o, JsArray) && k == "length" || k == "prototype") : attribute & Attr.READONLY == 0);
		}
		d.setOwn("enumerable", virtual ? (Std.isOfType(o, JsArray) && k != "length") : attribute & Attr.HIDDEN == 0);
		d.setOwn("configurable", virtual ? (Std.isOfType(o, JsFunction) && k != "prototype" || Std.isOfType(o, JsArray) && k != "length") : attribute & Attr.LOCKED == 0);
		return d;
	}

	static function defineProperties(o:JsObject, props:Dynamic):Void {
		var p = toObject(props);
		for (k in ownPropertyKeys(p)) if (enumerableOwn(p, k)) defineProperty(o, k, get(p, k));
	}

	public static function defineProperty(o:JsObject, k:String, desc:Dynamic):Void {
		if (!isObject(desc)) error("TypeError", "Property description must be an object: " + Seed.text(desc));
		if (!o.hasOwn(k) && Std.isOfType(o, JsFunction) && hasOwnKey(o, k)) o.setOwn(k, get(o, k), k == "prototype" ? Attr.HIDDEN | Attr.LOCKED : Attr.HIDDEN | Attr.READONLY);
		var exists = o.hasOwn(k);
		var old = exists ? o.attr(k) : Attr.HIDDEN | Attr.READONLY | Attr.LOCKED;
		if (exists && old & Attr.LOCKED != 0) {
			if (has(desc, "value") && !(old & Attr.READONLY != 0 && sameValue(get(desc, "value"), o.getOwn(k))) && old & Attr.READONLY != 0) error("TypeError", "Cannot redefine property: " + Symbols.functionName(k));
			if (has(desc, "get") || has(desc, "set") || Seed.truth(get(desc, "configurable"))) error("TypeError", "Cannot redefine property: " + Symbols.functionName(k));
		}
		else if (!exists && !o.extensible) error("TypeError", "Cannot define property " + Symbols.functionName(k) + ", object is not extensible");
		function flag(name:String, bit:Int, attribute:Int):Int {
			if (!has(desc, name)) return attribute;
			return Seed.truth(get(desc, name)) ? attribute & ~bit : attribute | bit;
		}
		var attribute = old;
		attribute = flag("enumerable", Attr.HIDDEN, attribute);
		attribute = flag("configurable", Attr.LOCKED, attribute);
		if (has(desc, "get") || has(desc, "set")) {
			var current = exists ? o.getOwn(k) : null;
			var acc = Std.isOfType(current, Accessor) ? (current : Accessor) : new Accessor(null, null);
			if (has(desc, "get")) {
				var g = get(desc, "get");
				acc.getter = g == undef() ? null : g;
			}
			if (has(desc, "set")) {
				var s = get(desc, "set");
				acc.setter = s == undef() ? null : s;
			}
			o.setOwn(k, acc, attribute & ~Attr.READONLY);
			return;
		}
		attribute = flag("writable", Attr.READONLY, attribute);
		var value = has(desc, "value") ? get(desc, "value") : exists && !Std.isOfType(o.getOwn(k), Accessor) ? o.getOwn(k) : undef();
		if (Std.isOfType(o, JsArray)) {
			var a:JsArray = cast o;
			if (k == "length") {
				setLength(a, value);
				return;
			}
			var i = index(k);
			if (i >= 0) {
				if (attribute == 0) {
					setIndex(a, i, value);
					return;
				}
				if (i < a.items.length) a.items[Std.int(i)] = hole;
				if (i >= a.length) a.length = i + 1;
			}
		}
		o.setOwn(k, value, attribute);
	}

	static function integrity(v:Dynamic, freeze:Bool):Void {
		if (!isObject(v)) return;
		var o:JsObject = v;
		if (Std.isOfType(o, JsArray)) {
			// (elements move to ordinary properties, which carry attributes)
			var a:JsArray = cast o;
			var items = a.items;
			a.items = [];
			for (i in 0...items.length) if (items[i] != hole) a.setOwn(Std.string(i), items[i]);
		}
		if (o.ownNames() != null) for (k in o.ownNames().copy()) {
			var attribute = o.attr(k) | Attr.LOCKED;
			if (freeze && !Std.isOfType(o.getOwn(k), Accessor)) attribute |= Attr.READONLY;
			o.setOwn(k, o.getOwn(k), attribute);
		}
		o.extensible = false;
	}

	static function testIntegrity(v:Dynamic, frozen:Bool):Bool {
		if (!isObject(v)) return true;
		var o:JsObject = v;
		if (o.extensible) return false;
		if (Std.isOfType(o, JsArray) && (cast o : JsArray).items.length > 0) return false;
		if (o.ownNames() != null) for (k in o.ownNames().copy()) {
			var attribute = o.attr(k);
			if (attribute & Attr.LOCKED == 0) return false;
			if (frozen && !Std.isOfType(o.getOwn(k), Accessor) && attribute & Attr.READONLY == 0) return false;
		}
		return true;
	}

	// Primitive wrapper objects (Object("x"), new Number(1)).
	public static function wrap(v:Dynamic):JsObject {
		var o = new JsObject(Std.isOfType(v, String) ? StringProto : Std.isOfType(v, Bool) ? BooleanProto : Std.isOfType(v, Symbols.JsSymbol) ? SymbolProto : NumberProto);
		o.setOwn("\x00@primitive", v, Attr.HIDDEN);
		if (Std.isOfType(v, String)) {
			var s:String = v;
			for (i in 0...s.length) o.setOwn(Std.string(i), s.charAt(i), Attr.READONLY | Attr.LOCKED);
			o.setOwn("length", s.length, Attr.HIDDEN | Attr.READONLY | Attr.LOCKED);
		}
		return o;
	}

	// (this value of a String/Number/Boolean method: the primitive, or a wrapper's)
	public static function primitive(t:Dynamic, type:String):Dynamic {
		if (isObject(t) && (t : JsObject).hasOwn("\x00@primitive")) t = (t : JsObject).getOwn("\x00@primitive");
		if (Seed.typeOf(t) != type) error("TypeError", type.charAt(0).toUpperCase() + type.substr(1) + ".prototype method called on incompatible receiver " + Seed.text(t));
		return t;
	}
}
