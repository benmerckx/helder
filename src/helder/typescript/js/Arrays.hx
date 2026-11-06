package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Symbols.JsSymbol;
import helder.typescript.js.Lib.*;
import helder.typescript.js.Builtins.*;
import helder.typescript.js.Objects.*;
import helder.typescript.js.Strings.*;
import helder.typescript.js.Collections.*;
import helder.typescript.js.Globals.*;

// Array's built-ins: Array and its prototype, and the array-likes its generic methods take.
@:access(helder.typescript.js.Builtins)
@:access(helder.typescript.js.Objects)
@:access(helder.typescript.js.Strings)
@:access(helder.typescript.js.Collections)
@:access(helder.typescript.js.Globals)
class Arrays {
	public static function arrayLikeList(o:Dynamic):Array<Dynamic> {
		if (!isObject(o)) return error("TypeError", "CreateListFromArrayLike called on non-object");
		var n = Std.int(Math.min(lengthOf(o), 1e7));
		return [for (i in 0...n) get(o, i)];
	}

	public static function lengthOf(o:Dynamic):Float {
		if (Std.isOfType(o, JsArray)) return (o : JsArray).length;
		var n = toIntegerOrInfinity(get(o, "length"));
		return Math.max(0, Math.min(n, 9007199254740991.0));
	}

	// Array
	static function hasAt(o:Dynamic, i:Float):Bool {
		if (Std.isOfType(o, JsArray)) {
			var a:JsArray = cast o;
			if (a.nums != null) {
				if (i < a.nums.length) return true;
			}
			else if (i < a.items.length) return a.items[Std.int(i)] != hole;
		}
		return has(o, Seed.numberText(i));
	}

	static function setAt(o:Dynamic, i:Float, v:Dynamic):Void put(o, i, v);

	static function deleteAt(o:Dynamic, i:Float):Void remove(o, Seed.numberText(i));

	static function relative(v:Dynamic, len:Float):Float {
		var n = toIntegerOrInfinity(v);
		return n < 0 ? Math.max(len + n, 0) : Math.min(n, len);
	}

	static function setupArray():Void {
		var p = ArrayProto;
		var c = constructor("Array", 1, p, (_, a, nt) -> {
			var r:JsArray = cast array(a.length == 1 && isNumber(a[0]) ? [] : a.copy());
			if (a.length == 1 && isNumber(a[0])) setLength(r, a[0]);
			r.proto = protoFrom(nt, ArrayProto);
			return r;
		});
		getter(c, "\x00@@species", t -> t);
		var unscopables = new JsObject(null);
		for (name in ["at", "copyWithin", "entries", "fill", "find", "findIndex", "findLast", "findLastIndex", "flat", "flatMap", "includes", "keys", "toReversed", "toSorted", "toSpliced", "values"]) unscopables.setOwn(name, true);
		p.setOwn("\x00@@unscopables", unscopables, Attr.HIDDEN | Attr.READONLY);
		method(c, "isArray", 1, (_, a, _) -> Std.isOfType(arg(a, 0), JsArray));
		method(c, "of", 0, (_, a, _) -> array(a.copy()));
		method(c, "from", 1, (_, a, _) -> {
			var source = arg(a, 0);
			var f = arg(a, 1);
			var mapped = f != undef();
			if (mapped) callback(f);
			if (source == null || source == undef()) error("TypeError", Seed.text(source) + " is not iterable");
			var values = getKey(source, Symbols.iterator, source) != undef() ? toList(source) : arrayLikeList(toObject(source));
			if (mapped) for (i in 0...values.length) values[i] = call(f, arg(a, 2), [values[i], i]);
			return array(values);
		});
		method(p, "push", 1, (t, a, _) -> {
			if (Std.isOfType(t, JsArray)) {
				var arr:JsArray = cast t;
				if (arr.nums != null && arr.extensible && Lambda.foreach(a, isNumber)) {
					for (v in a) arr.nums.push(v);
					arr.length = arr.nums.length;
					return arr.length;
				}
				if (arr.items.length == arr.length && arr.extensible) {
					for (v in a) arr.items.push(v);
					arr.length = arr.items.length;
					return arr.length;
				}
			}
			var o = toObject(t);
			var n = lengthOf(o);
			for (v in a) setAt(o, n++, v);
			put(o, "length", n);
			return n;
		});
		method(p, "pop", 0, (t, _, _) -> {
			if (Std.isOfType(t, JsArray) && (t : JsArray).nums != null && (t : JsArray).nums.length > 0) {
				var arr:JsArray = cast t;
				arr.length--;
				return arr.nums.pop();
			}
			var o = toObject(t);
			var n = lengthOf(o);
			if (n == 0) {
				put(o, "length", 0);
				return undef();
			}
			var v = get(o, n - 1);
			deleteAt(o, n - 1);
			put(o, "length", n - 1);
			return v;});
		method(p, "shift", 0, (t, _, _) -> {
			var o = toObject(t);
			var n = lengthOf(o);
			if (n == 0) {
				put(o, "length", 0);
				return undef();
			}
			if (Std.isOfType(o, JsArray)) {
				var arr:JsArray = cast o;
				if (arr.nums != null && arr.extensible) {
					arr.length--;
					return arr.nums.shift();
				}
				if (arr.items.length == n && arr.extensible) {
					var v = arr.items.shift();
					arr.length--;
					return v == hole ? undef() : v;
				}
			}
			var v = get(o, 0);
			var i:Float = 1;
			while (i < n) {
				if (hasAt(o, i)) setAt(o, i - 1, get(o, i)); else deleteAt(o, i - 1);
				i++;
			}
			deleteAt(o, n - 1);
			put(o, "length", n - 1);
			return v;
		});
		method(p, "unshift", 1, (t, a, _) -> {
			var o = toObject(t);
			var n = lengthOf(o);
			var count = a.length;
			var i = n;
			while (i > 0) {
				i--;
				if (hasAt(o, i)) setAt(o, i + count, get(o, i)); else deleteAt(o, i + count);
			}
			for (j in 0...count) setAt(o, j, a[j]);
			put(o, "length", n + count);
			return n + count;});
		method(p, "join", 1, (t, a, _) -> join(toObject(t), arg(a, 0) == undef() ? "," : Seed.text(arg(a, 0))));
		method(p, "toString", 0, (t, _, _) -> {
			var o = toObject(t);
			var j = get(o, "join");
			return isCallable(j) ? call(j, o, []) : objectToString(o);});
		method(p, "toLocaleString", 0, (t, _, _) -> join(toObject(t), ","));
		method(p, "slice", 2, (t, a, _) -> {
			var o = toObject(t);
			var n = lengthOf(o);
			var start = relative(arg(a, 0), n);
			var end = arg(a, 1) == undef() ? n : relative(arg(a, 1), n);
			var out = new JsArray(ArrayProto);
			var i = start;
			var k:Float = 0;
			while (i < end) {
				if (hasAt(o, i)) setIndex(out, k, get(o, i));
				k++;
				i++;
			}
			out.length = Math.max(k, 0);
			return out;});
		method(p, "at", 1, (t, a, _) -> {
			var o = toObject(t);
			var n = lengthOf(o);
			var i = toIntegerOrInfinity(arg(a, 0));
			if (i < 0) i += n;
			return i < 0 || i >= n ? undef() : get(o, i);});
		method(p, "indexOf", 1, (t, a, _) -> {
			var o = toObject(t);
			var n = lengthOf(o);
			var i = arg(a, 1) == undef() ? 0 : toIntegerOrInfinity(arg(a, 1));
			if (i < 0) i = Math.max(i + n, 0);
			var x = arg(a, 0);
			while (i < n) {
				if (hasAt(o, i) && Seed.strictEq(get(o, i), x)) return i;
				i++;
			}
			return -1;});
		method(p, "lastIndexOf", 1, (t, a, _) -> {
			var o = toObject(t);
			var n = lengthOf(o);
			var i = a.length < 2 ? n - 1 : toIntegerOrInfinity(arg(a, 1));
			if (i < 0) i += n; else i = Math.min(i, n - 1);
			var x = arg(a, 0);
			while (i >= 0) {
				if (hasAt(o, i) && Seed.strictEq(get(o, i), x)) return i;
				i--;
			}
			return -1;});
		method(p, "includes", 1, (t, a, _) -> {
			var o = toObject(t);
			var n = lengthOf(o);
			var i = arg(a, 1) == undef() ? 0 : toIntegerOrInfinity(arg(a, 1));
			if (i < 0) i = Math.max(i + n, 0);
			var x = arg(a, 0);
			while (i < n) {
				if (sameValueZero(get(o, i), x)) return true;
				i++;
			}
			return false;});
		for (name in ["map", "filter", "forEach", "some", "every", "find", "findIndex", "findLast", "findLastIndex"]) method(p, name, 1, function(t:Dynamic, a:Array<Dynamic>, _:Dynamic):Dynamic {
			var o = toObject(t);
			var n = lengthOf(o);
			var f = callback(arg(a, 0));
			var self = arg(a, 1);
			var out = new JsArray(ArrayProto);
			if (name == "map") out.length = n;
			var reverse = name == "findLast" || name == "findLastIndex";
			var visitAll = StringTools.startsWith(name, "find");
			var i:Float = reverse ? n - 1 : 0;
			while (i >= 0 && i < n) {
				if (visitAll || hasAt(o, i)) {
					var v = get(o, i);
					var result = call(f, self, [v, i, o]);
					switch (name) {
						case "map": setIndex(out, i, result);
						case "filter": if (Seed.truth(result)) setIndex(out, out.length, v);
						case "some": if (Seed.truth(result)) return true;
						case "every": if (!Seed.truth(result)) return false;
						case "find" | "findLast": if (Seed.truth(result)) return v;
						case "findIndex" | "findLastIndex": if (Seed.truth(result)) return i;
						case _:
					}
				}
				i += reverse ? -1 : 1;
			}
			return switch (name) {
				case "map" | "filter": out;
				case "some": false;
				case "every": true;
				case "find" | "findLast" | "forEach": undef();
				case _: -1;
			};
		});
		for (name in ["reduce", "reduceRight"]) method(p, name, 1, (t, a, _) -> {
			var o = toObject(t);
			var n = lengthOf(o);
			var f = callback(arg(a, 0));
			var reverse = name == "reduceRight";
			var i:Float = reverse ? n - 1 : 0;
			var acc = arg(a, 1);
			var ready = a.length >= 2;
			while (i >= 0 && i < n) {
				if (hasAt(o, i)) {
					if (!ready) {
						acc = get(o, i);
						ready = true;
					} else acc = call(f, undef(), [acc, get(o, i), i, o]);
				}
				i += reverse ? -1 : 1;
			}
			if (!ready) error("TypeError", "Reduce of empty array with no initial value");
			return acc;
		});
		method(p, "reverse", 0, (t, _, _) -> {
			var o = toObject(t);
			var n = lengthOf(o);
			var left:Float = 0;
			while (left < Math.ffloor(n / 2)) {
				var right = n - left - 1;
				var l = hasAt(o, left), r = hasAt(o, right);
				var lv = get(o, left), rv = get(o, right);
				if (r) setAt(o, left, rv); else deleteAt(o, left);
				if (l) setAt(o, right, lv); else deleteAt(o, right);
				left++;
			}
			return o;});
		method(p, "toReversed", 0, (t, _, _) -> {
			var o = toObject(t);
			var n = lengthOf(o);
			return array([for (i in 0...Std.int(n)) get(o, n - 1 - i)]);});
		method(p, "fill", 1, (t, a, _) -> {
			var o = toObject(t);
			var n = lengthOf(o);
			var i = relative(arg(a, 1), n);
			var end = arg(a, 2) == undef() ? n : relative(arg(a, 2), n);
			while (i < end) setAt(o, i++, arg(a, 0));
			return o;});
		method(p, "concat", 1, (t, a, _) -> {
			var out = new JsArray(ArrayProto);
			for (item in ([toObject(t)] : Array<Dynamic>).concat(a)) {
				var spreadable = getKey(item, "\x00@@isConcatSpreadable", item);
				if (spreadable == undef() ? Std.isOfType(item, JsArray) : Seed.truth(spreadable)) {
					var n = lengthOf(item);
					var i:Float = 0;
					var start = out.length;
					while (i < n) {
						if (hasAt(item, i)) setIndex(out, start + i, get(item, i));
						i++;
					}
					out.length = start + n;
				}
				else setIndex(out, out.length, item);
			}
			return out;
		});
		method(p, "keys", 0, (t, _, _) -> new JsIterator(ArrayIteratorProto, toObject(t), "keys"));
		method(p, "entries", 0, (t, _, _) -> new JsIterator(ArrayIteratorProto, toObject(t), "entries"));
		var values = native("values", 0, (t, _, _) -> new JsIterator(ArrayIteratorProto, toObject(t), "values"));
		p.setOwn("values", values, Attr.HIDDEN);
		p.setOwn(Symbols.iterator, values, Attr.HIDDEN);
		for (name in ["splice", "toSpliced"]) method(p, name, 2, (t, a, _) -> {
			var o = toObject(t);
			var n = lengthOf(o);
			var start = relative(arg(a, 0), n);
			var count = a.length == 0 ? 0 : a.length == 1 ? n - start : Math.min(Math.max(toIntegerOrInfinity(arg(a, 1)), 0), n - start);
			var inserted = a.slice(2);
			if (name == "toSpliced") {
				var out = [];
				var i:Float = 0;
				while (i < start) out.push(get(o, i++));
				for (v in inserted) out.push(v);
				i = start + count;
				while (i < n) out.push(get(o, i++));
				return array(out);
			}
			var removed = new JsArray(ArrayProto);
			var k:Float = 0;
			while (k < count) {
				if (hasAt(o, start + k)) setIndex(removed, k, get(o, start + k));
				k++;
			}
			removed.length = count;
			var delta = inserted.length - count;
			if (delta < 0) {
				var i = start;
				while (i < n - count) {
					var from = i + count, to = i + inserted.length;
					if (hasAt(o, from)) setAt(o, to, get(o, from)); else deleteAt(o, to);
					i++;
				}
				var j = n;
				while (j > n + delta) {
					deleteAt(o, j - 1);
					j--;
				}
			}
			else if (delta > 0) {
				var i = n - count;
				while (i > start) {
					var from = i + count - 1, to = i + inserted.length - 1;
					if (hasAt(o, from)) setAt(o, to, get(o, from)); else deleteAt(o, to);
					i--;
				}
			}
			for (j in 0...inserted.length) setAt(o, start + j, inserted[j]);
			put(o, "length", n + delta);
			return removed;
		});
		for (name in ["sort", "toSorted"]) method(p, name, 1, (t, a, _) -> {
			var cmp = arg(a, 0);
			if (cmp != undef()) callback(cmp);
			var o = toObject(t);
			var n = lengthOf(o);
			var present = [];
			var undefineds = 0;
			var i:Float = 0;
			while (i < n) {
				if (name == "toSorted" || hasAt(o, i)) {
					var v = get(o, i);
					if (v == undef()) undefineds++; else present.push(v);
				}
				i++;
			}
			present = mergeSort(present, (x, y) -> cmp == undef() ? compareStrings(Seed.text(x), Seed.text(y)) : {var r = Seed.numeric(call(cmp, undef(), [x, y])); r > 0 ? 1 : r < 0 ? -1 : 0;});
			var target:Dynamic = name == "sort" ? o : new JsArray(ArrayProto);
			var k:Float = 0;
			for (v in present) setAt(target, k++, v);
			for (_ in 0...undefineds) setAt(target, k++, undef());
			if (name == "sort") while (k < n) deleteAt(target, k++);
			return target;
		});
		method(p, "copyWithin", 2, (t, a, _) -> {
			var o = toObject(t);
			var n = lengthOf(o);
			var target = relative(arg(a, 0), n), start = relative(arg(a, 1), n), end = arg(a, 2) == undef() ? n : relative(arg(a, 2), n);
			var count = Math.min(end - start, n - target);
			var direction:Float = 1;
			if (start < target && target < start + count) {
				direction = -1;
				start += count - 1;
				target += count - 1;
			}
			while (count > 0) {
				if (hasAt(o, start)) setAt(o, target, get(o, start)); else deleteAt(o, target);
				start += direction;
				target += direction;
				count--;
			}
			return o;});
		method(p, "flat", 0, (t, a, _) -> {
			var o = toObject(t);
			var out = new JsArray(ArrayProto);
			var depth = arg(a, 0) == undef() ? 1 : Math.max(toIntegerOrInfinity(arg(a, 0)), 0);
			flatten(out, o, depth + 1);
			return out;});
		method(p, "flatMap", 1, (t, a, _) -> {
			var o = toObject(t);
			var f = callback(arg(a, 0));
			var out = new JsArray(ArrayProto);
			var n = lengthOf(o);
			var i:Float = 0;
			while (i < n) {
				if (hasAt(o, i)) flatten(out, call(f, arg(a, 1), [get(o, i), i, o]), 1);
				i++;
			}
			return out;});
		method(p, "with", 2, (t, a, _) -> {
			var o = toObject(t);
			var n = lengthOf(o);
			var i = toIntegerOrInfinity(arg(a, 0));
			if (i < 0) i += n;
			if (i < 0 || i >= n) error("RangeError", "Invalid index : " + Seed.text(arg(a, 0)));
			return array([for (j in 0...Std.int(n)) j == i ? arg(a, 1) : get(o, j)]);});
	}

	static function join(o:Dynamic, sep:String):String {
		var n = lengthOf(o);
		var b = new StringBuf();
		var i:Float = 0;
		if (cycle.indexOf(o) >= 0) return "";
		cycle.push(o);
		try {
			while (i < n) {
				if (i > 0) b.add(sep);
				var v = get(o, i++);
				if (v != null && v != undef()) b.add(Seed.text(v));
			}
		}
		catch (e:Dynamic) {
			cycle.pop();
			throw e;
		}
		cycle.pop();
		return b.toString();
	}
	static var cycle:Array<Dynamic> = [];
	static function flatten(out:JsArray, v:Dynamic, depth:Float):Void {
		if (depth > 0 && Std.isOfType(v, JsArray)) {
			var n = lengthOf(v);
			var i:Float = 0;
			while (i < n) {
				if (hasAt(v, i)) flatten(out, get(v, i), depth - 1);
				i++;
			}
		}
		else setIndex(out, out.length, v);
	}

	static function mergeSort(values:Array<Dynamic>, cmp:(Dynamic, Dynamic) -> Int):Array<Dynamic> {
		if (values.length < 2) return values;
		var mid = values.length >> 1;
		var left = mergeSort(values.slice(0, mid), cmp), right = mergeSort(values.slice(mid), cmp);
		var out = [];
		var i = 0, j = 0;
		while (i < left.length && j < right.length) out.push(cmp(left[i], right[j]) <= 0 ? left[i++] : right[j++]);
		while (i < left.length) out.push(left[i++]);
		while (j < right.length) out.push(right[j++]);
		return out;
	}
}
