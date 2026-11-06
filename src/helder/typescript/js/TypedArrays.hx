package helder.typescript.js;

import haxe.io.Bytes;
import helder.typescript.js.Values;
import helder.typescript.js.Buffers;
import helder.typescript.js.Lib.*;

// A typed array: a view of an ArrayBuffer's bytes as elements of one kind
// (Int8Array... Float64Array), little-endian as every platform helder
// runs on. Its elements are integer-indexed (Lib's get and put come here
// for them): an index out of bounds reads undefined, a write there is
// dropped.
class JsTypedArray extends JsObject {
	public var buffer:JsBuffer;
	public var offset:Int;
	// (elements; -1: tracking a resizable buffer's length)
	public var count:Int;
	public final kind:Int;

	public function new(proto:JsObject, kind:Int, buffer:JsBuffer, offset:Int, count:Int) {
		super(proto);
		this.kind = kind;
		this.buffer = buffer;
		this.offset = offset;
		this.count = count;
	}

	// its elements now (0 when its buffer is detached or it is out of bounds)
	public function length():Int {
		var data = buffer.data;
		if (data == null) return 0;
		var w = TypedArrays.WIDTHS[kind];
		if (count < 0) return offset > data.length ? 0 : Std.int((data.length - offset) / w);
		return offset + count * w > data.length ? 0 : count;
	}

	public inline function bytes():Bytes return buffer.data;

	override public function tag():String return TypedArrays.NAMES[kind];
}

@:access(helder.typescript.js.Builtins)
@:access(helder.typescript.js.Buffers)
class TypedArrays {
	public static inline var INT8 = 0;
	public static inline var UINT8 = 1;
	public static inline var UINT8C = 2;
	public static inline var INT16 = 3;
	public static inline var UINT16 = 4;
	public static inline var INT32 = 5;
	public static inline var UINT32 = 6;
	public static inline var FLOAT16 = 7;
	public static inline var FLOAT32 = 8;
	public static inline var FLOAT64 = 9;
	public static final NAMES = ["Int8Array", "Uint8Array", "Uint8ClampedArray", "Int16Array", "Uint16Array", "Int32Array", "Uint32Array", "Float16Array", "Float32Array", "Float64Array"];
	public static final WIDTHS = [1, 1, 1, 2, 2, 4, 4, 2, 4, 8];

	// %TypedArray%.prototype, and each kind's prototype and constructor
	public static var Proto:JsObject;
	static var protos:Array<JsObject> = [];
	static var ctors:Array<JsFunction> = [];
	static var ready = false;

	// ---- elements

	// element i (in bounds: the caller checked) as a number
	public static function read(t:JsTypedArray, i:Int):Float {
		var b = t.buffer.data, p = t.offset + i * WIDTHS[t.kind];
		return switch t.kind {
			case INT8:
				var v = b.get(p);
				v >= 128 ? v - 256 : v;
			case UINT8 | UINT8C: b.get(p);
			case INT16:
				var v = b.getUInt16(p);
				v >= 32768 ? v - 65536 : v;
			case UINT16: b.getUInt16(p);
			case INT32: b.getInt32(p);
			case UINT32:
				var v = b.getInt32(p);
				v < 0 ? v + 4294967296.0 : v;
			case FLOAT16: Buffers.halfValue(b.getUInt16(p));
			case FLOAT32: b.getFloat(p);
			case _: b.getDouble(p);
		}
	}

	// element i (in bounds) set to the number v
	public static function write(t:JsTypedArray, i:Int, v:Float):Void {
		var b = t.buffer.data, p = t.offset + i * WIDTHS[t.kind];
		switch t.kind {
			case INT8 | UINT8: b.set(p, toInt32(v) & 255);
			case UINT8C: b.set(p, clamp(v));
			case INT16 | UINT16: b.setUInt16(p, toInt32(v) & 65535);
			case INT32 | UINT32: b.setInt32(p, toInt32(v));
			case FLOAT16: b.setUInt16(p, Buffers.halfBits(v));
			case FLOAT32: b.setFloat(p, v);
			case _: b.setDouble(p, v);
		}
	}

	// (Uint8ClampedArray's: 0 to 255, rounded half to even)
	static function clamp(v:Float):Int {
		if (!(v > 0)) return 0;
		if (v >= 255) return 255;
		var f = Math.floor(v), d = v - f;
		return Std.int(d > 0.5 ? f + 1 : d < 0.5 ? f : (f % 2 == 0 ? f : f + 1));
	}

	// (what Lib's get and put call for an integer index: set when installed,
	// as only then there are typed arrays, so a program without them links
	// none of their code)
	public static var elementGet:(JsTypedArray, Float) -> Dynamic = null;
	public static var elementSet:(JsTypedArray, Float, Dynamic) -> Void = null;

	// Lib's get of an integer index: the element, or undefined
	public static function getIndex(t:JsTypedArray, i:Float):Dynamic {
		if (i < 0 || i >= t.length() || i != Math.ffloor(i)) return undef();
		return read(t, Std.int(i));
	}

	// Lib's put of an integer index: the element set when in bounds (the
	// value made a number first, as the specification's order has it)
	public static function setIndex(t:JsTypedArray, i:Float, v:Dynamic):Void {
		var n = Seed.numeric(v);
		if (i >= 0 && i < t.length() && i == Math.ffloor(i)) write(t, Std.int(i), n);
	}

	// ---- making them

	static function allocate(kind:Int, length:Float, proto:JsObject):JsTypedArray {
		var b = Buffers.allocate(length * WIDTHS[kind], length * WIDTHS[kind], false, Buffers.BufferProto);
		return new JsTypedArray(proto, kind, b, 0, Std.int(length));
	}

	// a new array of kind with values (numbers made of each)
	public static function of(kind:Int, values:Array<Dynamic>):JsTypedArray {
		install();
		var t = allocate(kind, values.length, protos[kind]);
		for (i in 0...values.length) write(t, i, Seed.numeric(values[i]));
		return t;
	}

	// a Uint8Array (or another kind of one byte) over bytes, sharing them:
	// how helder's Haxe Bytes come to the program (Interop)
	public static function ofBytes(bytes:Bytes, kind = UINT8):JsTypedArray {
		install();
		var b = new JsBuffer(Buffers.BufferProto, bytes, bytes.length, false);
		return new JsTypedArray(protos[kind], kind, b, 0, Std.int(bytes.length / WIDTHS[kind]));
	}

	// the bytes a typed array, a DataView or an ArrayBuffer views: its
	// buffer's own when it views all of it (writes are seen both ways),
	// else a copy of its part
	public static function bytesOf(v:Dynamic):Null<Bytes> {
		if (Std.isOfType(v, JsBuffer)) return (v : JsBuffer).data;
		var data:Bytes = null, start = 0, size = 0;
		if (Std.isOfType(v, JsTypedArray)) {
			var t:JsTypedArray = v;
			data = t.buffer.data;
			start = t.offset;
			size = t.length() * WIDTHS[t.kind];
		} else if (Std.isOfType(v, JsDataView)) {
			var d:JsDataView = v;
			data = d.buffer.data;
			start = d.offset;
			size = d.length();
		} else return null;
		if (data == null) return null;
		return start == 0 && size == data.length ? data : data.sub(start, size);
	}

	static function typed(v:Dynamic):JsTypedArray {
		if (!Std.isOfType(v, JsTypedArray)) return error("TypeError", "this is not a typed array.");
		return v;
	}

	// (a typed array its method works on: not detached nor out of bounds)
	static function valid(v:Dynamic):JsTypedArray {
		var t = typed(v);
		if (t.buffer.data == null) return error("TypeError", "Cannot perform %TypedArray%.prototype method on a detached ArrayBuffer");
		return t;
	}

	// new T(...) for kind: a length, an array-like or iterable, another typed array, a buffer (offset, length)
	static function create(kind:Int, a:Array<Dynamic>, nt:Dynamic):Dynamic {
		if (nt == undef()) return error("TypeError", "Constructor " + NAMES[kind] + " requires 'new'");
		var proto = protoFrom(nt, protos[kind]);
		var first = arg(a, 0);
		if (!isObject(first)) return allocate(kind, Buffers.toIndex(first), proto);
		if (Std.isOfType(first, JsBuffer)) {
			var b:JsBuffer = first, w = WIDTHS[kind];
			var offset = Buffers.toIndex(arg(a, 1));
			if (offset % w != 0) return error("RangeError", "start offset of " + NAMES[kind] + " should be a multiple of " + w);
			var len = arg(a, 2), count:Float = -1;
			if (len != undef()) count = Buffers.toIndex(len);
			Buffers.attached(b);
			var size = b.length();
			if (count < 0 && !b.resizable) {
				if (size % w != 0) return error("RangeError", "byte length of " + NAMES[kind] + " should be a multiple of " + w);
				if (offset > size) return error("RangeError", "Start offset " + offset + " is outside the bounds of the buffer");
				count = (size - offset) / w;
			} else if (count >= 0 && offset + count * w > size) return error("RangeError", "Invalid typed array length: " + count);
			return new JsTypedArray(proto, kind, b, Std.int(offset), Std.int(count));
		}
		var values:Array<Dynamic> = if (Std.isOfType(first, JsTypedArray)) {
			var src:JsTypedArray = valid(first);
			[for (i in 0...src.length()) read(src, i)];
		} else if (getKey(first, Symbols.iterator, first) != undef()) toList(first) else Arrays.arrayLikeList(first);
		var t = allocate(kind, values.length, proto);
		for (i in 0...values.length) write(t, i, Seed.numeric(values[i]));
		return t;
	}

	// a new typed array like t (its kind, through its constructor's species)
	static function like(t:JsTypedArray, length:Int):JsTypedArray {
		var ctor = get(t, "constructor"), species:Dynamic = ctors[t.kind];
		if (ctor != undef()) {
			if (!isObject(ctor)) return error("TypeError", "object.constructor is not an object");
			var s = get(ctor, "\x00@@species");
			if (s != null && s != undef()) species = s;
		}
		if (species == ctors[t.kind]) return allocate(t.kind, length, protos[t.kind]);
		var r = valid(construct(species, [(length : Float)], species));
		if (r.length() < length) return error("TypeError", "the species constructor made a typed array too short");
		return r;
	}

	static function relative(v:Dynamic, length:Int, otherwise:Int):Int {
		if (v == undef()) return otherwise;
		var n = toIntegerOrInfinity(v);
		return Std.int(n < 0 ? Math.max(length + n, 0) : Math.min(n, length));
	}

	static function numberCompare(a:Float, b:Float):Int {
		if (Math.isNaN(a)) return Math.isNaN(b) ? 0 : 1;
		if (Math.isNaN(b)) return -1;
		if (a < b) return -1;
		if (a > b) return 1;
		// (-0 before +0)
		if (a == 0 && b == 0) {
			var na = 1 / a < 0, nb = 1 / b < 0;
			return na == nb ? 0 : na ? -1 : 1;
		}
		return 0;
	}

	static function sorted(t:JsTypedArray, cmp:Dynamic):Array<Float> {
		var values = [for (i in 0...t.length()) read(t, i)];
		var c:(Float, Float) -> Int = cmp == undef() ? numberCompare : (x, y) -> {
			var r = Seed.numeric(call(cmp, undef(), [x, y]));
			return Math.isNaN(r) ? 0 : r < 0 ? -1 : r > 0 ? 1 : 0;
		};
		haxe.ds.ArraySort.sort(values, c);
		return values;
	}

	// ---- the built-ins

	public static function install():Void {
		if (ready) return;
		ready = true;
		elementGet = getIndex;
		elementSet = setIndex;
		Builtins.installBuffers();
		Proto = new JsObject(Builtins.ObjectProto);
		var abstractCtor = Builtins.native("TypedArray", 0, (_, _, _) -> error("TypeError", "Abstract class TypedArray not directly constructable"), true);
		abstractCtor.setOwn("prototype", Proto, Attr.HIDDEN | Attr.READONLY | Attr.LOCKED);
		Proto.setOwn("constructor", abstractCtor, Attr.HIDDEN);
		Builtins.getter(abstractCtor, "\x00@@species", t -> t);
		methods();
		Builtins.method(abstractCtor, "from", 1, (t, a, _) -> {
			var source = arg(a, 0), fn = arg(a, 1), self = arg(a, 2);
			if (fn != undef()) Builtins.callback(fn);
			var values = getKey(source, Symbols.iterator, source) != undef() ? toList(source) : Arrays.arrayLikeList(toObject(source));
			if (fn != undef()) values = [for (i in 0...values.length) call(fn, self, [values[i], (i : Float)])];
			return construct(t, [Lib.array(values)], t);
		});
		Builtins.method(abstractCtor, "of", 0, (t, a, _) -> construct(t, [Lib.array(a.copy())], t));
		var global:JsObject = Builtins.globals.get("globalThis");
		for (kind in 0...NAMES.length) {
			var k = kind;
			var proto = new JsObject(Proto);
			var c = Builtins.constructor(NAMES[k], 3, proto, (_, a, nt) -> create(k, a, nt));
			c.proto = abstractCtor;
			Builtins.constant(c, "BYTES_PER_ELEMENT", (WIDTHS[k] : Float));
			Builtins.constant(proto, "BYTES_PER_ELEMENT", (WIDTHS[k] : Float));
			protos[k] = proto;
			ctors[k] = c;
			if (global != null) global.setOwn(NAMES[k], c, Attr.HIDDEN);
		}
	}

	static function methods() {
		var p = Proto;
		Builtins.getter(p, "length", t -> (typed(t).length() : Float));
		Builtins.getter(p, "byteLength", t -> {
			var x = typed(t);
			return (x.length() * WIDTHS[x.kind] : Float);
		});
		Builtins.getter(p, "byteOffset", t -> {
			var x = typed(t);
			return (x.buffer.data == null || x.length() == 0 && x.count != 0 ? 0 : x.offset : Float);
		});
		Builtins.getter(p, "buffer", t -> typed(t).buffer);
		Builtins.getter(p, Symbols.toStringTag, t -> Std.isOfType(t, JsTypedArray) ? NAMES[(t : JsTypedArray).kind] : undef());
		function each(name:String, arity:Int, fn:(JsTypedArray, Array<Dynamic>) -> Dynamic)
			Builtins.method(p, name, arity, (t, a, _) -> fn(valid(t), a));
		each("at", 1, (t, a) -> {
			var n = t.length(), i = toIntegerOrInfinity(arg(a, 0));
			if (i < 0) i += n;
			return i < 0 || i >= n ? undef() : read(t, Std.int(i));
		});
		each("set", 1, (t, a) -> {
			var source = arg(a, 0), offset = toIntegerOrInfinity(arg(a, 1));
			if (offset < 0) return error("RangeError", "offset is out of bounds");
			var values:Array<Dynamic> = Std.isOfType(source, JsTypedArray) ? {
				var s = valid(source);
				[for (i in 0...s.length()) read(s, i)];
			} : Arrays.arrayLikeList(toObject(source));
			if (offset + values.length > t.length()) return error("RangeError", "offset is out of bounds");
			for (i in 0...values.length) write(t, Std.int(offset) + i, Seed.numeric(values[i]));
			return undef();
		});
		each("subarray", 2, (t, a) -> {
			var n = t.length(), start = relative(arg(a, 0), n, 0), end = relative(arg(a, 1), n, n);
			var count = Std.int(Math.max(end - start, 0));
			var ctor = get(t, "constructor"), species:Dynamic = ctors[t.kind];
			if (ctor != undef() && isObject(ctor)) {
				var s = get(ctor, "\x00@@species");
				if (s != null && s != undef()) species = s;
			}
			return construct(species, [t.buffer, (t.offset + start * WIDTHS[t.kind] : Float), (count : Float)], species);
		});
		each("slice", 2, (t, a) -> {
			var n = t.length(), start = relative(arg(a, 0), n, 0), end = relative(arg(a, 1), n, n);
			var count = Std.int(Math.max(end - start, 0));
			var r = like(t, count);
			for (i in 0...count) write(r, i, read(t, start + i));
			return r;
		});
		each("fill", 1, (t, a) -> {
			var v = Seed.numeric(arg(a, 0)), n = t.length(), start = relative(arg(a, 1), n, 0), end = relative(arg(a, 2), n, n);
			for (i in start...end) write(t, i, v);
			return t;
		});
		each("copyWithin", 2, (t, a) -> {
			var n = t.length(), target = relative(arg(a, 0), n, 0), start = relative(arg(a, 1), n, 0), end = relative(arg(a, 2), n, n);
			var count = Std.int(Math.min(end - start, n - target)), w = WIDTHS[t.kind];
			if (count > 0) t.buffer.data.blit(t.offset + target * w, t.buffer.data, t.offset + start * w, count * w);
			return t;
		});
		each("reverse", 0, (t, a) -> {
			var n = t.length();
			for (i in 0...Std.int(n / 2)) {
				var x = read(t, i);
				write(t, i, read(t, n - 1 - i));
				write(t, n - 1 - i, x);
			}
			return t;
		});
		each("toReversed", 0, (t, a) -> {
			var n = t.length(), r = allocate(t.kind, n, protos[t.kind]);
			for (i in 0...n) write(r, i, read(t, n - 1 - i));
			return r;
		});
		each("sort", 1, (t, a) -> {
			var cmp = arg(a, 0);
			if (cmp != undef()) Builtins.callback(cmp);
			var values = sorted(t, cmp);
			for (i in 0...Std.int(Math.min(values.length, t.length()))) write(t, i, values[i]);
			return t;
		});
		each("toSorted", 1, (t, a) -> {
			var cmp = arg(a, 0);
			if (cmp != undef()) Builtins.callback(cmp);
			var values = sorted(t, cmp), r = allocate(t.kind, values.length, protos[t.kind]);
			for (i in 0...values.length) write(r, i, values[i]);
			return r;
		});
		each("with", 2, (t, a) -> {
			var n = t.length(), i = toIntegerOrInfinity(arg(a, 0));
			if (i < 0) i += n;
			var v = Seed.numeric(arg(a, 1));
			if (i < 0 || i >= t.length()) return error("RangeError", "Invalid typed array index");
			var r = allocate(t.kind, n, protos[t.kind]);
			for (j in 0...n) write(r, j, j == i ? v : read(t, j));
			return r;
		});
		each("join", 1, (t, a) -> {
			var sep = arg(a, 0) == undef() ? "," : Seed.text(arg(a, 0));
			return [for (i in 0...t.length()) Seed.numberText(read(t, i))].join(sep);
		});
		each("toString", 0, (t, a) -> [for (i in 0...t.length()) Seed.numberText(read(t, i))].join(","));
		each("toLocaleString", 0, (t, a) -> [for (i in 0...t.length()) Seed.text(callMethod(read(t, i), "toLocaleString", []))].join(","));
		each("indexOf", 1, (t, a) -> {
			var n = t.length(), v = arg(a, 0), i = relative(arg(a, 1), n, 0);
			if (!isNumber(v)) return -1.0;
			while (i < n) {
				if (read(t, i) == (v : Float)) return (i : Float);
				i++;
			}
			return -1.0;
		});
		each("lastIndexOf", 1, (t, a) -> {
			var n = t.length(), v = arg(a, 0);
			var i = a.length > 1 ? Std.int(Math.min(toIntegerOrInfinity(arg(a, 1)) < 0 ? n + toIntegerOrInfinity(arg(a, 1)) : toIntegerOrInfinity(arg(a, 1)), n - 1)) : n - 1;
			if (!isNumber(v)) return -1.0;
			while (i >= 0) {
				if (read(t, i) == (v : Float)) return (i : Float);
				i--;
			}
			return -1.0;
		});
		each("includes", 1, (t, a) -> {
			var n = t.length(), v = arg(a, 0), i = relative(arg(a, 1), n, 0);
			if (!isNumber(v)) return false;
			while (i < n) {
				if (sameValueZero(read(t, i), v)) return true;
				i++;
			}
			return false;
		});
		function visit(name:String, fn:(JsTypedArray, Dynamic, Dynamic) -> Dynamic)
			each(name, 1, (t, a) -> fn(t, Builtins.callback(arg(a, 0)), arg(a, 1)));
		visit("forEach", (t, f, self) -> {
			for (i in 0...t.length()) call(f, self, [read(t, i), (i : Float), t]);
			return undef();
		});
		visit("map", (t, f, self) -> {
			var n = t.length(), r = like(t, n);
			for (i in 0...n) write(r, i, Seed.numeric(call(f, self, [read(t, i), (i : Float), t])));
			return r;
		});
		visit("filter", (t, f, self) -> {
			var kept:Array<Float> = [];
			for (i in 0...t.length()) {
				var v = read(t, i);
				if (Seed.truth(call(f, self, [v, (i : Float), t]))) kept.push(v);
			}
			var r = like(t, kept.length);
			for (i in 0...kept.length) write(r, i, kept[i]);
			return r;
		});
		visit("every", (t, f, self) -> {
			for (i in 0...t.length()) if (!Seed.truth(call(f, self, [read(t, i), (i : Float), t]))) return false;
			return true;
		});
		visit("some", (t, f, self) -> {
			for (i in 0...t.length()) if (Seed.truth(call(f, self, [read(t, i), (i : Float), t]))) return true;
			return false;
		});
		visit("find", (t, f, self) -> {
			for (i in 0...t.length()) {
				var v = read(t, i);
				if (Seed.truth(call(f, self, [v, (i : Float), t]))) return v;
			}
			return undef();
		});
		visit("findIndex", (t, f, self) -> {
			for (i in 0...t.length()) if (Seed.truth(call(f, self, [read(t, i), (i : Float), t]))) return (i : Float);
			return -1.0;
		});
		visit("findLast", (t, f, self) -> {
			var i = t.length() - 1;
			while (i >= 0) {
				var v = read(t, i);
				if (Seed.truth(call(f, self, [v, (i : Float), t]))) return v;
				i--;
			}
			return undef();
		});
		visit("findLastIndex", (t, f, self) -> {
			var i = t.length() - 1;
			while (i >= 0) {
				if (Seed.truth(call(f, self, [read(t, i), (i : Float), t]))) return (i : Float);
				i--;
			}
			return -1.0;
		});
		function fold(name:String, backwards:Bool)
			each(name, 1, (t, a) -> {
				var f = Builtins.callback(arg(a, 0)), n = t.length(), i = backwards ? n - 1 : 0, step = backwards ? -1 : 1;
				var acc:Dynamic;
				if (a.length > 1) acc = a[1] else {
					if (n == 0) return error("TypeError", "Reduce of empty array with no initial value");
					acc = read(t, i);
					i += step;
				}
				while (i >= 0 && i < n) {
					acc = call(f, undef(), [acc, read(t, i), (i : Float), t]);
					i += step;
				}
				return acc;
			});
		fold("reduce", false);
		fold("reduceRight", true);
		each("keys", 0, (t, a) -> new JsIterator(Builtins.ArrayIteratorProto, t, "keys"));
		each("entries", 0, (t, a) -> new JsIterator(Builtins.ArrayIteratorProto, t, "entries"));
		var values = Builtins.native("values", 0, (t, _, _) -> new JsIterator(Builtins.ArrayIteratorProto, valid(t), "values"));
		p.setOwn("values", values, Attr.HIDDEN);
		p.setOwn(Symbols.iterator, values, Attr.HIDDEN);
	}
}
