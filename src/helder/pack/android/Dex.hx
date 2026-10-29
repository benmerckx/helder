package helder.pack.android;

import haxe.io.Bytes;

// A minimal DEX writer (Dalvik executable, version 035: what every Android
// runs), for the few Java classes an app needs as glue (Glue): classes
// with fields and methods whose code is given as Dalvik instructions
// (16-bit units) built against the file's pools (Refs: the index of a
// string, type, field or method, known once every class is collected).
// The layout the format specifies: the header, the id sections sorted as
// the runtime requires (strings by their UTF-16 units, types by their
// descriptor's string, protos by return type then parameters, fields and
// methods by class, name, then type or proto), the class definitions, then
// the data (type lists, code items, string data, class data) and the map
// of every section; the SHA-1 signature over everything after it, then the
// Adler-32 checksum. `check` reads a file back and verifies that structure
// (the checks: tests/pack).
// Ported from hxmc (hxmc.android.Dex), MIT.
class Dex {
	public static inline var PUBLIC = 0x1;
	public static inline var PRIVATE = 0x2;
	public static inline var PROTECTED = 0x4;
	public static inline var STATIC = 0x8;
	public static inline var FINAL = 0x10;
	public static inline var NATIVE = 0x100;
	public static inline var CONSTRUCTOR = 0x10000;

	static inline var NO_INDEX = -1;

	// the map's item types
	static inline var HEADER = 0x0000;
	static inline var STRING_ID = 0x0001;
	static inline var TYPE_ID = 0x0002;
	static inline var PROTO_ID = 0x0003;
	static inline var FIELD_ID = 0x0004;
	static inline var METHOD_ID = 0x0005;
	static inline var CLASS_DEF = 0x0006;
	static inline var MAP_LIST = 0x1000;
	static inline var TYPE_LIST = 0x1001;
	static inline var CLASS_DATA = 0x2000;
	static inline var CODE = 0x2001;
	static inline var STRING_DATA = 0x2002;

	public static function write(classes:Array<DexClass>):Bytes {
		var pools = new Pools();
		// (collected: every name, then the code's references)
		for (c in classes) {
			pools.type(c.name);
			pools.type(c.superName);
			for (i in c.interfaces)
				pools.type(i);
			for (f in c.fields)
				pools.field(c.name, f.name, f.type);
			for (m in c.methods) {
				pools.method(c.name, m.name, m.ret, m.params);
				if (m.code != null) m.code.insns(pools);
			}
		}
		pools.sort();
		var nS = pools.strings.length, nT = pools.types.length, nP = pools.protos.length, nF = pools.fields.length, nM = pools.methods.length,
			nC = classes.length;
		var at = 0x70;
		var stringIdsAt = at;
		at += 4 * nS;
		var typeIdsAt = at;
		at += 4 * nT;
		var protoIdsAt = at;
		at += 12 * nP;
		var fieldIdsAt = at;
		at += 8 * nF;
		var methodIdsAt = at;
		at += 8 * nM;
		var classDefsAt = at;
		at += 32 * nC;
		var dataAt = at;
		// the data, after the ids
		var data = new helder.pack.Buf(4096);
		inline function pos()
			return dataAt + data.len;
		inline function align4()
			while (data.len % 4 != 0)
				data.u8(0);
		// type lists (the protos' parameters, the classes' interfaces; one of each)
		var lists = new Map<String, Int>(), nLists = 0;
		var listsAt = pos();
		function typeList(types:Array<String>):Int {
			if (types.length == 0) return 0;
			var key = types.join(",");
			var o = lists.get(key);
			if (o != null) return o;
			align4();
			o = pos();
			data.u32(types.length);
			for (t in types)
				data.u16(pools.typeIndex(t));
			lists.set(key, o);
			nLists++;
			return o;
		}
		var protoParams = [for (p in pools.protos) typeList(p.params)];
		var interfaces = [for (c in classes) typeList(c.interfaces)];
		// code items
		align4();
		var codeAt = pos(), nCode = 0;
		var codeOffsets = new Map<String, Int>();
		for (c in classes)
			for (m in c.methods)
				if (m.code != null) {
					align4();
					codeOffsets.set(c.name + "->" + m.name + pools.protoKey(m.ret, m.params), pos());
					var insns = m.code.insns(pools);
					data.u16(m.code.registers);
					data.u16(m.code.ins);
					data.u16(m.code.outs);
					data.u16(0); // tries
					data.u32(0); // debug info
					data.u32(insns.length);
					for (u in insns)
						data.u16(u);
					nCode++;
				}
		// string data (MUTF-8: the strings here are ASCII)
		var stringDataAt = pos();
		var stringOffsets = [];
		for (s in pools.strings) {
			stringOffsets.push(pos());
			data.uleb(s.length);
			data.str(s);
			data.u8(0);
		}
		// class data: fields, then direct methods (static, private,
		// constructors) and virtual ones, each list by method index
		var classDataAt = pos();
		var classData = [];
		for (c in classes) {
			classData.push(pos());
			var statics = [for (f in c.fields) if (f.access & STATIC != 0) f], fields = [for (f in c.fields) if (f.access & STATIC == 0) f];
			var direct = [], virtual = [];
			for (m in c.methods)
				(m.access & (STATIC | PRIVATE | CONSTRUCTOR) != 0 ? direct : virtual).push(m);
			data.uleb(statics.length);
			data.uleb(fields.length);
			data.uleb(direct.length);
			data.uleb(virtual.length);
			for (list in [statics, fields]) {
				var idx = [for (f in list) {i: pools.fieldIndex(c.name, f.name, f.type), f: f}];
				idx.sort((a, b) -> a.i - b.i);
				var last = 0;
				for (e in idx) {
					data.uleb(e.i - last);
					data.uleb(e.f.access);
					last = e.i;
				}
			}
			for (list in [direct, virtual]) {
				var idx = [for (m in list) {i: pools.methodIndex(c.name, m.name, m.ret, m.params), m: m}];
				idx.sort((a, b) -> a.i - b.i);
				var last = 0;
				for (e in idx) {
					data.uleb(e.i - last);
					data.uleb(e.m.access);
					data.uleb(e.m.code == null ? 0 : codeOffsets.get(c.name + "->" + e.m.name + pools.protoKey(e.m.ret, e.m.params)));
					last = e.i;
				}
			}
		}
		// the map
		align4();
		var mapAt = pos();
		var map = [
			[HEADER, 1, 0],
			[STRING_ID, nS, stringIdsAt],
			[TYPE_ID, nT, typeIdsAt],
			[PROTO_ID, nP, protoIdsAt],
			[FIELD_ID, nF, fieldIdsAt],
			[METHOD_ID, nM, methodIdsAt],
			[CLASS_DEF, nC, classDefsAt],
			[TYPE_LIST, nLists, listsAt],
			[CODE, nCode, codeAt],
			[STRING_DATA, nS, stringDataAt],
			[CLASS_DATA, nC, classDataAt],
			[MAP_LIST, 1, mapAt]
		].filter(e -> e[1] > 0);
		data.u32(map.length);
		for (e in map) {
			data.u16(e[0]);
			data.u16(0);
			data.u32(e[1]);
			data.u32(e[2]);
		}
		// the header and the ids
		var out = new helder.pack.Buf(dataAt + data.len);
		out.str("dex\n035\x00");
		out.zeros(24); // checksum, signature
		out.u32(dataAt + data.len);
		out.u32(0x70);
		out.u32(0x12345678);
		out.u32(0); // link
		out.u32(0);
		out.u32(mapAt);
		for (s in [[nS, stringIdsAt], [nT, typeIdsAt], [nP, protoIdsAt], [nF, fieldIdsAt], [nM, methodIdsAt], [nC, classDefsAt]]) {
			out.u32(s[0]);
			out.u32(s[0] == 0 ? 0 : s[1]);
		}
		out.u32(data.len);
		out.u32(dataAt);
		for (o in stringOffsets)
			out.u32(o);
		for (t in pools.types)
			out.u32(pools.stringIndex(t));
		for (i in 0...nP) {
			var p = pools.protos[i];
			out.u32(pools.stringIndex(p.shorty));
			out.u32(pools.typeIndex(p.ret));
			out.u32(protoParams[i]);
		}
		for (f in pools.fields) {
			out.u16(pools.typeIndex(f.cls));
			out.u16(pools.typeIndex(f.type));
			out.u32(pools.stringIndex(f.name));
		}
		for (m in pools.methods) {
			out.u16(pools.typeIndex(m.cls));
			out.u16(pools.protoIndex(m.ret, m.params));
			out.u32(pools.stringIndex(m.name));
		}
		for (i in 0...nC) {
			var c = classes[i];
			out.u32(pools.typeIndex(c.name));
			out.u32(c.access);
			out.u32(pools.typeIndex(c.superName));
			out.u32(interfaces[i]);
			out.u32(NO_INDEX); // source file
			out.u32(0); // annotations
			out.u32(classData[i]);
			out.u32(0); // static values
		}
		out.buf(data);
		var b = out.toBytes();
		b.blit(12, haxe.crypto.Sha1.make(b.sub(32, b.length - 32)), 0, 20);
		var a = new haxe.crypto.Adler32();
		a.update(b, 12, b.length - 12);
		b.setInt32(8, a.get());
		return b;
	}

	// ---- reading back

	// the file's structure verified (header, signature, checksum, the map,
	// the order and references of the ids, class data and code): the
	// problems found (none: empty); classes gets "Lname; method(params)ret" lines
	public static function check(b:Bytes, ?classes:Array<String>):Array<String> {
		var errors = [];
		function err(s:String)
			errors.push(s);
		if (b.length < 0x70 || b.getString(0, 4) != "dex\n") return ["not a DEX file"];
		var u32 = b.getInt32, u16 = b.getUInt16;
		if (u32(32) != b.length) err("file_size " + u32(32) + " is not the file's " + b.length);
		if (u32(36) != 0x70) err("header_size");
		if (u32(40) != 0x12345678) err("endian_tag");
		var a = new haxe.crypto.Adler32();
		a.update(b, 12, b.length - 12);
		if (a.get() != u32(8)) err("checksum");
		if (haxe.crypto.Sha1.make(b.sub(32, b.length - 32)).compare(b.sub(12, 20)) != 0) err("signature");
		var nS = u32(56), sAt = u32(60), nT = u32(64), tAt = u32(68), nP = u32(72), pAt = u32(76), nF = u32(80), fAt = u32(84), nM = u32(88),
			mAt = u32(92), nC = u32(96), cAt = u32(100), dataSize = u32(104), dataAt = u32(108);
		if (dataAt + dataSize != b.length) err("the data section does not end the file");
		if (dataAt % 4 != 0 || dataSize % 4 != 0) err("the data section is not aligned");
		function uleb(at:Array<Int>):Int {
			var v = 0, shift = 0, c;
			do {
				c = b.get(at[0]++);
				v |= (c & 0x7f) << shift;
				shift += 7;
			} while (c & 0x80 != 0);
			return v;
		}
		// the map: sections in order, each where the header says
		var map = u32(52), n = u32(map), last = -1, seen = new Map<Int, Array<Int>>();
		for (i in 0...n) {
			var e = map + 4 + 12 * i, type = u16(e), count = u32(e + 4), off = u32(e + 8);
			if (off <= last) err("map: section 0x" + StringTools.hex(type) + " out of order");
			if (off >= b.length) err("map: section 0x" + StringTools.hex(type) + " outside the file");
			last = off;
			seen.set(type, [count, off]);
		}
		for (s in [[HEADER, 1, 0], [STRING_ID, nS, sAt], [TYPE_ID, nT, tAt], [PROTO_ID, nP, pAt], [FIELD_ID, nF, fAt], [METHOD_ID, nM, mAt], [CLASS_DEF, nC, cAt],
			[MAP_LIST, 1, map]])
			if (s[1] > 0) {
				var m = seen.get(s[0]);
				if (m == null || m[0] != s[1] || m[1] != s[2]) err("map: section 0x" + StringTools.hex(s[0]) + " is not the header's");
			}
		if (map % 4 != 0) err("map: not aligned");
		// strings, sorted; types sorted and naming strings
		var strings = [];
		for (i in 0...nS) {
			var at = [u32(sAt + 4 * i)];
			if (at[0] < dataAt) err("string " + i + " outside the data");
			var len = uleb(at), s = b.getString(at[0], len);
			if (b.get(at[0] + len) != 0) err("string " + i + " has no NUL");
			if (i > 0 && !(strings[i - 1] < s)) err("strings out of order at " + i);
			strings.push(s);
		}
		function str(i:Int):String {
			if (i >= 0 && i < nS) return strings[i];
			err("a string index " + i);
			return "?";
		}
		var types = [for (i in 0...nT) u32(tAt + 4 * i)];
		for (i in 1...nT)
			if (types[i] <= types[i - 1]) err("types out of order at " + i);
		function type(i:Int):String {
			if (i >= 0 && i < nT) return str(types[i]);
			err("a type index " + i);
			return "?";
		}
		function list(off:Int):Array<Int> {
			if (off == 0) return [];
			if (off % 4 != 0) err("a type list not aligned");
			return [for (k in 0...u32(off)) u16(off + 4 + 2 * k)];
		}
		var protos = [];
		for (i in 0...nP) {
			var at = pAt + 12 * i, ret = u32(at + 4), params = list(u32(at + 8));
			var shorty = [for (t in [ret].concat(params)) {var d = type(t); d.charAt(0) == "[" ? "L" : d.charAt(0);}].join("");
			if (str(u32(at)) != shorty) err("proto " + i + ": shorty " + str(u32(at)) + ", not " + shorty);
			var key = [ret].concat(params);
			if (i > 0) {
				var prev = protos[i - 1], c = 0;
				c = prev[0] - key[0];
				var k = 1;
				while (c == 0 && k < prev.length && k < key.length) {
					c = prev[k] - key[k];
					k++;
				}
				if (c == 0) c = prev.length - key.length;
				if (c >= 0) err("protos out of order at " + i);
			}
			protos.push(key);
		}
		function protoString(p:Int)
			return "(" + [for (k in 1...protos[p].length) type(protos[p][k])].join("") + ")" + type(protos[p][0]);
		var prev = [-1, -1, -1];
		for (i in 0...nF) {
			var at = fAt + 8 * i, k = [u16(at), u32(at + 4), u16(at + 2)];
			if (k[0] < prev[0] || (k[0] == prev[0] && (k[1] < prev[1] || (k[1] == prev[1] && k[2] <= prev[2])))) err("fields out of order at " + i);
			type(k[0]);
			type(k[2]);
			str(k[1]);
			prev = k;
		}
		prev = [-1, -1, -1];
		var methods = [];
		for (i in 0...nM) {
			var at = mAt + 8 * i, k = [u16(at), u32(at + 4), u16(at + 2)];
			if (k[0] < prev[0] || (k[0] == prev[0] && (k[1] < prev[1] || (k[1] == prev[1] && k[2] <= prev[2])))) err("methods out of order at " + i);
			if (k[2] >= nP) err("method " + i + ": a proto index");
			methods.push(k);
			prev = k;
		}
		// classes: their data, the code of each method
		for (i in 0...nC) {
			var at = cAt + 32 * i, name = type(u32(at));
			type(u32(at + 8));
			for (t in list(u32(at + 12)))
				type(t);
			var cd = u32(at + 24);
			if (cd == 0) continue;
			var p = [cd];
			var counts = [for (_ in 0...4) uleb(p)];
			for (k in 0...2) {
				var idx = 0;
				for (j in 0...counts[k]) {
					var d = uleb(p);
					if (j > 0 && d == 0) err(name + ": fields out of order");
					idx += d;
					uleb(p);
				}
			}
			for (k in 2...4) {
				var idx = 0;
				for (j in 0...counts[k]) {
					var d = uleb(p);
					if (j > 0 && d == 0) err(name + ": methods out of order");
					idx += d;
					var access = uleb(p), code = uleb(p);
					if (idx >= nM) {
						err(name + ": a method index");
						continue;
					}
					var m = methods[idx];
					if (type(m[0]) != name) err(name + ": method " + str(m[1]) + " of another class");
					var sig = str(m[1]) + protoString(m[2]);
					if (classes != null) classes.push(name + " " + sig);
					if (k == 2 && access & (STATIC | PRIVATE | CONSTRUCTOR) == 0) err(name + "." + sig + ": a virtual method among the direct ones");
					if (k == 3 && access & (STATIC | PRIVATE | CONSTRUCTOR) != 0) err(name + "." + sig + ": a direct method among the virtual ones");
					if ((code == 0) != (access & (NATIVE | 0x400) != 0)) err(name + "." + sig + ": code and flags disagree");
					if (code != 0) {
						if (code % 4 != 0 || code < dataAt) err(name + "." + sig + ": its code is not aligned in the data");
						var ins = (access & STATIC != 0 ? 0 : 1);
						for (t in 1...protos[m[2]].length) {
							var d = type(protos[m[2]][t]);
							ins += d == "J" || d == "D" ? 2 : 1;
						}
						if (u16(code + 2) != ins) err(name + "." + sig + ": ins_size " + u16(code + 2) + ", not " + ins);
						if (u16(code) < ins) err(name + "." + sig + ": fewer registers than ins");
						if (code + 16 + 2 * u32(code + 12) > b.length) err(name + "." + sig + ": its code outside the file");
					}
				}
			}
		}
		return errors;
	}
}

typedef DexClass = {
	name:String,
	access:Int,
	superName:String,
	interfaces:Array<String>,
	fields:Array<{name:String, type:String, access:Int}>,
	methods:Array<DexMethod>
};

typedef DexMethod = {
	name:String,
	ret:String,
	params:Array<String>,
	access:Int,
	?code:DexCode
};

// a method's code: its registers (the arguments are the last `ins`), the
// most argument words a call in it passes, the instructions
typedef DexCode = {registers:Int, ins:Int, outs:Int, insns:Refs->Array<Int>};

// the indices of the file's pools, for the instructions
interface Refs {
	function type(desc:String):Int;
	function string(s:String):Int;
	function field(cls:String, name:String, type:String):Int;
	function method(cls:String, name:String, ret:String, params:Array<String>):Int;
}

// what the classes name: added while collecting (indices 0 then), sorted once
private class Pools implements Refs {
	public var strings:Array<String> = [];
	public var types:Array<String> = [];
	public var protos:Array<{ret:String, params:Array<String>, shorty:String}> = [];
	public var fields:Array<{cls:String, name:String, type:String}> = [];
	public var methods:Array<{cls:String, name:String, ret:String, params:Array<String>}> = [];

	final stringIdx = new Map<String, Int>();
	final typeIdx = new Map<String, Int>();
	final protoIdx = new Map<String, Int>();
	final fieldIdx = new Map<String, Int>();
	final methodIdx = new Map<String, Int>();
	var sorted = false;

	public function new() {}

	public function string(s:String):Int {
		if (!sorted && !stringIdx.exists(s)) {
			stringIdx.set(s, -1);
			strings.push(s);
		}
		return stringIndex(s);
	}

	public function type(d:String):Int {
		if (!sorted && !typeIdx.exists(d)) {
			typeIdx.set(d, -1);
			types.push(d);
			string(d);
		}
		return typeIndex(d);
	}

	public function protoKey(ret:String, params:Array<String>):String
		return "(" + params.join("") + ")" + ret;

	function proto(ret:String, params:Array<String>) {
		var k = protoKey(ret, params);
		if (sorted || protoIdx.exists(k)) return;
		protoIdx.set(k, -1);
		var shorty = [for (t in [ret].concat(params)) t.charAt(0) == "[" ? "L" : t.charAt(0)].join("");
		protos.push({ret: ret, params: params, shorty: shorty});
		string(shorty);
		type(ret);
		for (p in params)
			type(p);
	}

	public function field(cls:String, name:String, t:String):Int {
		var k = cls + "->" + name + ":" + t;
		if (!sorted && !fieldIdx.exists(k)) {
			fieldIdx.set(k, -1);
			fields.push({cls: cls, name: name, type: t});
			type(cls);
			type(t);
			string(name);
		}
		return fieldIndex(cls, name, t);
	}

	public function method(cls:String, name:String, ret:String, params:Array<String>):Int {
		var k = cls + "->" + name + protoKey(ret, params);
		if (!sorted && !methodIdx.exists(k)) {
			methodIdx.set(k, -1);
			methods.push({cls: cls, name: name, ret: ret, params: params});
			type(cls);
			string(name);
			proto(ret, params);
		}
		return methodIndex(cls, name, ret, params);
	}

	public function stringIndex(s:String):Int
		return sorted ? stringIdx.get(s) : 0;

	public function typeIndex(d:String):Int
		return sorted ? typeIdx.get(d) : 0;

	public function protoIndex(ret:String, params:Array<String>):Int
		return sorted ? protoIdx.get(protoKey(ret, params)) : 0;

	public function fieldIndex(cls:String, name:String, t:String):Int
		return sorted ? fieldIdx.get(cls + "->" + name + ":" + t) : 0;

	public function methodIndex(cls:String, name:String, ret:String, params:Array<String>):Int
		return sorted ? methodIdx.get(cls + "->" + name + protoKey(ret, params)) : 0;

	static function cmp(a:Int, b:Int):Int
		return a < b ? -1 : a > b ? 1 : 0;

	// (the strings are ASCII: their UTF-16 order is the bytes')
	public function sort() {
		strings.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		for (i in 0...strings.length)
			stringIdx.set(strings[i], i);
		sorted = true;
		types.sort((a, b) -> cmp(stringIndex(a), stringIndex(b)));
		for (i in 0...types.length)
			typeIdx.set(types[i], i);
		protos.sort((a, b) -> {
			var c = cmp(typeIndex(a.ret), typeIndex(b.ret)), k = 0;
			while (c == 0 && k < a.params.length && k < b.params.length) {
				c = cmp(typeIndex(a.params[k]), typeIndex(b.params[k]));
				k++;
			}
			c != 0 ? c : cmp(a.params.length, b.params.length);
		});
		for (i in 0...protos.length)
			protoIdx.set(protoKey(protos[i].ret, protos[i].params), i);
		fields.sort((a, b) -> {
			var c = cmp(typeIndex(a.cls), typeIndex(b.cls));
			if (c == 0) c = cmp(stringIndex(a.name), stringIndex(b.name));
			c != 0 ? c : cmp(typeIndex(a.type), typeIndex(b.type));
		});
		for (i in 0...fields.length)
			fieldIdx.set(fields[i].cls + "->" + fields[i].name + ":" + fields[i].type, i);
		methods.sort((a, b) -> {
			var c = cmp(typeIndex(a.cls), typeIndex(b.cls));
			if (c == 0) c = cmp(stringIndex(a.name), stringIndex(b.name));
			c != 0 ? c : cmp(protoIndex(a.ret, a.params), protoIndex(b.ret, b.params));
		});
		for (i in 0...methods.length)
			methodIdx.set(methods[i].cls + "->" + methods[i].name + protoKey(methods[i].ret, methods[i].params), i);
	}
}
