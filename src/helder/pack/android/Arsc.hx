package helder.pack.android;

import haxe.io.Bytes;

// An APK's resource table (resources.arsc, what aapt2 links): the app's
// own resources (package 0x7f), each a type ("color", "mipmap", "style")
// and a name, with a value per configuration (the default, a density, the
// night mode): a file in the APK (res/...), a colour, a reference, a style
// (a parent and attributes). Its ids are 0x7f TT EEEE in the order added
// (types and entries). The writer of Apk's icons and splash theme; `dump`
// prints one back as text (the checks).
class Arsc {
	// Res_value types
	public static inline var REFERENCE = 0x01;
	public static inline var STRING = 0x03;
	public static inline var COLOR = 0x1c;

	// a configuration's density (dpi) and night mode (uiMode's night: yes)
	public static inline var XXXHDPI = 640;

	public final pkg:String;
	public final types:Array<{name:String, entries:Array<{name:String, values:Array<{config:Config, value:Value}>}>}> = [];

	public function new(pkg:String)
		this.pkg = pkg;

	// a resource's id (added when new) and its value in config
	public function add(type:String, name:String, value:Value, ?config:Config):Int {
		var t = Lambda.findIndex(types, t -> t.name == type);
		if (t < 0) {
			t = types.length;
			types.push({name: type, entries: []});
		}
		var es = types[t].entries, e = Lambda.findIndex(es, e -> e.name == name);
		if (e < 0) {
			e = es.length;
			es.push({name: name, values: []});
		}
		es[e].values.push({config: config ?? {}, value: value});
		return id(t, e);
	}

	static inline function id(t:Int, e:Int):Int
		return 0x7f000000 | ((t + 1) << 16) | e;

	// the id of a resource added, -1: none
	public function idOf(type:String, name:String):Int {
		var t = Lambda.findIndex(types, t -> t.name == type);
		if (t < 0) return -1;
		var e = Lambda.findIndex(types[t].entries, e -> e.name == name);
		return e < 0 ? -1 : id(t, e);
	}

	static function key(c:Config):String
		return (c.density ?? 0) + "/" + (c.night == true ? 1 : 0);

	public function encode():Bytes {
		var strings:Array<String> = [], keys:Array<String> = [];
		function str(s:String, into:Array<String>):Int {
			var i = into.indexOf(s);
			if (i < 0) {
				i = into.length;
				into.push(s);
			}
			return i;
		}
		for (t in types) for (e in t.entries) {
			str(e.name, keys);
			for (v in e.values) switch v.value {
				case FilePath(p): str(p, strings);
				case _:
			}
		}
		var body = new helder.pack.Buf(4096);
		var typePool = Axml.pool([for (t in types) t.name]), keyPool = Axml.pool(keys);
		for (ti => t in types) {
			// RES_TABLE_TYPE_SPEC_TYPE: each entry's configurations' changes
			body.u16(0x0202);
			body.u16(16);
			body.u32(16 + 4 * t.entries.length);
			body.u8(ti + 1);
			body.u8(0);
			body.u16(0);
			body.u32(t.entries.length);
			for (e in t.entries) {
				var flags = 0;
				for (v in e.values) {
					if (v.config.density != null) flags |= 0x0100;
					if (v.config.night == true) flags |= 0x1000;
				}
				body.u32(flags);
			}
			// RES_TABLE_TYPE_TYPE: one per configuration
			var configs:Array<Config> = [];
			for (e in t.entries) for (v in e.values) if (!Lambda.exists(configs, c -> key(c) == key(v.config))) configs.push(v.config);
			for (c in configs) {
				var entries = new helder.pack.Buf(256), offsets = [];
				for (e in t.entries) {
					var v = Lambda.find(e.values, v -> key(v.config) == key(c));
					if (v == null) {
						offsets.push(-1);
						continue;
					}
					offsets.push(entries.len);
					switch v.value {
						case Style(parent, items):
							entries.u16(16);
							entries.u16(0x0001); // FLAG_COMPLEX
							entries.u32(str(e.name, keys));
							entries.u32(parent);
							entries.u32(items.length);
							var sorted = items.copy();
							sorted.sort((a, b) -> a.attr < b.attr ? -1 : a.attr > b.attr ? 1 : 0);
							for (i in sorted) {
								entries.u32(i.attr);
								value(entries, i.value, strings);
							}
						case _:
							entries.u16(8);
							entries.u16(0);
							entries.u32(str(e.name, keys));
							value(entries, v.value, strings);
					}
				}
				var header = 20 + 64, start = header + 4 * offsets.length;
				body.u16(0x0201);
				body.u16(header);
				body.u32(start + entries.len);
				body.u8(ti + 1);
				body.u8(0);
				body.u16(0);
				body.u32(offsets.length);
				body.u32(start);
				// ResTable_config (64 bytes): density at 14, uiMode at 29
				var cfg = Bytes.alloc(64);
				cfg.setInt32(0, 64);
				if (c.density != null) cfg.setUInt16(14, c.density);
				if (c.night == true) cfg.set(29, 0x20);
				body.bytes(cfg);
				for (o in offsets)
					body.u32(o);
				body.buf(entries);
			}
		}
		// RES_TABLE_PACKAGE_TYPE: id, name (128 UTF-16 units), the pools' offsets
		var pkgHeader = 288;
		var pk = new helder.pack.Buf(pkgHeader + typePool.len + keyPool.len + body.len);
		pk.u16(0x0200);
		pk.u16(pkgHeader);
		pk.u32(pkgHeader + typePool.len + keyPool.len + body.len);
		pk.u32(0x7f);
		for (k in 0...128)
			pk.u16(k < pkg.length ? StringTools.fastCodeAt(pkg, k) : 0);
		pk.u32(pkgHeader);
		pk.u32(types.length);
		pk.u32(pkgHeader + typePool.len);
		pk.u32(keys.length);
		pk.u32(0);
		pk.buf(typePool);
		pk.buf(keyPool);
		pk.buf(body);
		// RES_TABLE_TYPE: the values' strings, the package
		var values = Axml.pool(strings);
		var out = new helder.pack.Buf(12 + values.len + pk.len);
		out.u16(0x0002);
		out.u16(12);
		out.u32(12 + values.len + pk.len);
		out.u32(1);
		out.buf(values);
		out.buf(pk);
		return out.toBytes();
	}

	static function value(b:helder.pack.Buf, v:Value, strings:Array<String>) {
		b.u16(8);
		b.u8(0);
		switch v {
			case FilePath(p):
				b.u8(STRING);
				b.u32(strings.indexOf(p));
			case Argb(argb):
				b.u8(COLOR);
				b.u32(argb);
			case Ref(id):
				b.u8(REFERENCE);
				b.u32(id);
			case Style(_, _): throw "Arsc: a style's attribute is a value, not a style";
		}
	}

	// the table as text: each resource's id, type/name, configuration and value
	public static function dump(b:Bytes):String {
		inline function u16(at:Int)
			return b.getUInt16(at);
		inline function u32(at:Int)
			return b.getInt32(at);
		function pool(at:Int):Array<String> {
			var n = u32(at + 8), start = u32(at + 20), header = u16(at + 2), out = [];
			for (k in 0...n) {
				var o = at + start + u32(at + header + 4 * k), len = u16(o), s = new StringBuf();
				for (i in 0...len)
					s.addChar(u16(o + 2 + 2 * i));
				out.push(s.toString());
			}
			return out;
		}
		inline function hex(v:Int)
			return "0x" + StringTools.hex(v, 8).toLowerCase();
		if (u16(0) != 0x0002) throw "Arsc: not a resource table";
		var values = pool(12), pk = 12 + u32(16);
		var types = pool(pk + u32(pk + 268)), keys = pool(pk + u32(pk + 276));
		var lines = [];
		var at = pk + u16(pk + 2), end = pk + u32(pk + 4);
		function val(at:Int):String {
			var t = b.get(at + 3), d = u32(at + 4);
			return switch t {
				case STRING: '"' + values[d] + '"';
				case REFERENCE: "@" + hex(d);
				case COLOR: "#" + StringTools.hex(d, 8).toLowerCase();
				case _: 't$t:' + hex(d);
			}
		}
		while (at < end) {
			var type = u16(at), size = u32(at + 4);
			if (type == 0x0201) {
				var ti = b.get(at + 8), n = u32(at + 12), start = u32(at + 16), cfg = at + 20;
				var c = [];
				if (u16(cfg + 14) != 0) c.push(u16(cfg + 14) + "dpi");
				if (b.get(cfg + 29) & 0x30 == 0x20) c.push("night");
				var config = c.length == 0 ? "default" : c.join("-");
				for (k in 0...n) {
					var o = u32(at + u16(at + 2) + 4 * k);
					if (o == -1) continue;
					var e = at + start + o, flags = u16(e + 2), name = keys[u32(e + 4)];
					var line = hex(0x7f000000 | (ti << 16) | k) + " " + types[ti - 1] + "/" + name + " (" + config + ") ";
					if (flags & 1 != 0) {
						var items = [];
						for (i in 0...u32(e + 12))
							items.push(hex(u32(e + 16 + 12 * i)) + "=" + val(e + 16 + 12 * i + 4));
						line += "parent=@" + hex(u32(e + 8)) + " " + items.join(" ");
					} else
						line += val(e + 8);
					lines.push(line);
				}
			}
			at += size;
		}
		return lines.join("\n");
	}
}

enum Value {
	// a file in the APK (res/...)
	FilePath(path:String);
	// 0xAARRGGBB
	Argb(argb:Int);
	Ref(id:Int);
	// a parent style's id, attributes' ids and values
	Style(parent:Int, items:Array<{attr:Int, value:Value}>);
}

typedef Config = {
	?density:Int,
	?night:Bool,
}
