package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Symbols.JsSymbol;
import helder.typescript.js.Lib.*;
import helder.typescript.js.Builtins.*;
import helder.typescript.js.Objects.*;
import helder.typescript.js.Arrays.*;
import helder.typescript.js.Strings.*;
import helder.typescript.js.Globals.*;

// Map, Set, WeakMap and WeakSet: their prototypes and the lookup indexes behind them.
@:access(helder.typescript.js.Builtins)
@:access(helder.typescript.js.Objects)
@:access(helder.typescript.js.Arrays)
@:access(helder.typescript.js.Strings)
@:access(helder.typescript.js.Globals)
class Collections {
	// Map and Set
	static function thisMap(t:Dynamic, isSet:Bool, name:String, weak = false):JsMap {
		if (!Std.isOfType(t, JsMap) || (t : JsMap).isSet != isSet || (t : JsMap).weak != weak) error("TypeError", "Method " + (weak ? "Weak" : "") + (isSet ? "Set" : "Map") + ".prototype." + name + " called on incompatible receiver " + Inspect.inspect(t));
		return t;
	}

	// (keys are compared with SameValueZero; an index maps each key to its slot)
	static function mapIndex(m:JsMap, k:Dynamic):Int {
		var id = mapKey(k);
		if (id != null) {
			var index = MapIndex.strings(m);
			return index.exists(id) ? index.get(id) : -1;
		}
		var index = MapIndex.objects(m);
		return index.exists(k) ? index.get(k) : -1;
	}

	static function mapKey(k:Dynamic):String {
		if (Std.isOfType(k, String)) return "s" + k;
		if (isNumber(k)) {
			var n:Float = k;
			return Math.isNaN(n) ? "NaN" : "n" + Seed.numberText(n == 0 ? 0 : n);
		}
		if (k == undef()) return "u";
		if (k == null) return "l";
		if (Std.isOfType(k, Bool)) return k ? "t" : "f";
		return null;
	}

	public static function mapPut(m:JsMap, k:Dynamic, v:Dynamic):JsMap {
		if (isNumber(k) && Seed.numeric(k) == 0) k = 0.0;
		if (m.isSet) v = k;
		var i = mapIndex(m, k);
		if (i >= 0) {
			m.values[i] = v;
			return m;
		}
		var slot = m.keys.length;
		m.keys.push(k);
		m.values.push(v);
		m.active.push(true);
		var id = mapKey(k);
		if (id != null) MapIndex.strings(m).set(id, slot); else MapIndex.objects(m).set(k, slot);
		return m;
	}

	static function mapDelete(m:JsMap, k:Dynamic):Bool {
		var i = mapIndex(m, k);
		if (i < 0) return false;
		m.active[i] = false;
		m.keys[i] = undef();
		m.values[i] = undef();
		var id = mapKey(k);
		if (id != null) MapIndex.strings(m).remove(id); else MapIndex.objects(m).remove(k);
		return true;
	}

	static function setupCollections():Void {
		for (isSet in [false, true]) {
			var p = isSet ? SetProto : MapProto;
			var name = isSet ? "Set" : "Map";
			var c = constructor(name, 0, p, (_, a, nt) -> {
				if (nt == undef()) error("TypeError", "Constructor " + name + " requires 'new'");
				var m = new JsMap(protoFrom(nt, p), isSet);
				var source = arg(a, 0);
				if (source != undef() && source != null) {
					var adder = get(m, isSet ? "add" : "set");
					for (v in toList(source)) {
						if (isSet) call(adder, m, [v]); else {
							if (!isObject(v)) error("TypeError", "Iterator value " + Seed.text(v) + " is not an entry object");
							call(adder, m, [get(v, 0), get(v, 1)]);
						}
					}
				}
				return m;
			});
			getter(c, "\x00@@species", t -> t);
			method(p, "get", 1, (t, a, _) -> {
				var m = thisMap(t, isSet, "get");
				var i = mapIndex(m, arg(a, 0));
				return i < 0 ? undef() : m.values[i];});
			method(p, "has", 1, (t, a, _) -> mapIndex(thisMap(t, isSet, "has"), arg(a, 0)) >= 0);
			if (isSet) method(p, "add", 1, (t, a, _) -> mapPut(thisMap(t, true, "add"), arg(a, 0), arg(a, 0)));
			else method(p, "set", 2, (t, a, _) -> mapPut(thisMap(t, false, "set"), arg(a, 0), arg(a, 1)));
			method(p, "delete", 1, (t, a, _) -> mapDelete(thisMap(t, isSet, "delete"), arg(a, 0)));
			method(p, "clear", 0, (t, _, _) -> {
				var m = thisMap(t, isSet, "clear");
				for (i in 0...m.active.length) m.active[i] = false;
				MapIndex.clear(m);
				return undef();});
			method(p, "forEach", 1, (t, a, _) -> {
				var m = thisMap(t, isSet, "forEach");
				var f = callback(arg(a, 0));
				var i = 0;
				while (i < m.keys.length) {
					if (m.active[i]) call(f, arg(a, 1), [m.values[i], m.keys[i], m]);
					i++;
				}
				return undef();});
			getter(p, "size", t -> {
				var m = thisMap(t, isSet, "size");
				var count = 0;
				for (v in m.active) if (v) count++;
				return count;});
			var iteratorProto = isSet ? SetIteratorProto : MapIteratorProto;
			method(p, "keys", 0, (t, _, _) -> new JsIterator(iteratorProto, thisMap(t, isSet, "keys"), isSet ? "values" : "keys"));
			method(p, "entries", 0, (t, _, _) -> new JsIterator(iteratorProto, thisMap(t, isSet, "entries"), "entries"));
			var values = native("values", 0, (t, _, _) -> new JsIterator(iteratorProto, thisMap(t, isSet, "values"), "values"));
			p.setOwn("values", values, Attr.HIDDEN);
			if (isSet) p.setOwn("keys", values, Attr.HIDDEN);
			p.setOwn(Symbols.iterator, isSet ? values : p.getOwn("entries"), Attr.HIDDEN);
			p.setOwn(Symbols.toStringTag, name, Attr.HIDDEN | Attr.READONLY);
			if (!isSet) method(c, "groupBy", 2, (_, a, _) -> groupBy(arg(a, 0), arg(a, 1), true));
		}
		// (weak collections hold their keys strongly)
		for (name in ["WeakMap", "WeakSet"]) {
			var isSet = name == "WeakSet";
			var p = new JsObject(ObjectProto);
			function key(k:Dynamic):Dynamic {
				if (!isObject(k) && !Std.isOfType(k, Symbols.JsSymbol)) error("TypeError", "Invalid value used " + (isSet ? "in weak set" : "as weak map key"));
				return k;
			}
			method(p, "has", 1, (t, a, _) -> {
				var m = thisMap(t, isSet, "has", true);
				return isObject(arg(a, 0)) && mapIndex(m, arg(a, 0)) >= 0;});
			method(p, "delete", 1, (t, a, _) -> {
				var m = thisMap(t, isSet, "delete", true);
				return isObject(arg(a, 0)) && mapDelete(m, arg(a, 0));});
			if (isSet) method(p, "add", 1, (t, a, _) -> mapPut(thisMap(t, true, "add", true), key(arg(a, 0)), arg(a, 0)));
			else {
				method(p, "get", 1, (t, a, _) -> {
					var m = thisMap(t, false, "get", true);
					var i = isObject(arg(a, 0)) ? mapIndex(m, arg(a, 0)) : -1;
					return i < 0 ? undef() : m.values[i];});
				method(p, "set", 2, (t, a, _) -> mapPut(thisMap(t, false, "set", true), key(arg(a, 0)), arg(a, 1)));
			}
			p.setOwn(Symbols.toStringTag, name, Attr.HIDDEN | Attr.READONLY);
			constructor(name, 0, p, (_, a, nt) -> {
				if (nt == undef()) error("TypeError", "Constructor " + name + " requires 'new'");
				var m = new JsMap(protoFrom(nt, p), isSet);
				m.weak = true;
				for (v in (arg(a, 0) == undef() || arg(a, 0) == null ? [] : toList(arg(a, 0)))) if (isSet) mapPut(m, key(v), v); else mapPut(m, key(get(v, 0)), get(v, 1));
				return m;
			});
		}
	}
}

// (Map and Set lookup indexes, created on first use)
class MapIndex {
	public static function strings(m:JsMap):Map<String, Int> {
		if (m.primitiveIndex == null) m.primitiveIndex = [];
		return m.primitiveIndex;
	}

	public static function objects(m:JsMap):haxe.ds.ObjectMap<Dynamic, Int> {
		if (m.objectIndex == null) m.objectIndex = new haxe.ds.ObjectMap();
		return m.objectIndex;
	}

	public static function clear(m:JsMap):Void {
		m.primitiveIndex = null;
		m.objectIndex = null;
	}
}
