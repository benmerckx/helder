package helder.pack.android;

import haxe.io.Bytes;

// Android's binary XML (AXML, what aapt2 compiles an AndroidManifest.xml
// to): a string pool (UTF-16), the resource ids of the android: attribute
// names (the first strings, in the same order), then the namespace and the
// elements as start and end chunks, attributes typed (Res_value): strings,
// decimal and hexadecimal integers, booleans and references to the
// framework's resources. The writer of Apk's manifest; `dump` prints one
// back as text (the checks: tests/pack). Ported from hxmc
// (hxmc.android.Axml), MIT.
class Axml {
	public static inline var ANDROID = "http://schemas.android.com/apk/res/android";

	// Res_value types
	public static inline var REFERENCE = 0x01;
	public static inline var STRING = 0x03;
	public static inline var INT_DEC = 0x10;
	public static inline var INT_HEX = 0x11;
	public static inline var BOOLEAN = 0x12;

	// the android: attributes Apk writes, by name: their resource ids (the framework's public.xml)
	public static final IDS = [
		"theme" => 0x01010000, "label" => 0x01010001, "name" => 0x01010003, "debuggable" => 0x0101000f, "exported" => 0x01010010,
		"hasCode" => 0x0101000c, "screenOrientation" => 0x0101001e, "configChanges" => 0x0101001f, "value" => 0x01010024,
		"minSdkVersion" => 0x0101020c, "versionCode" => 0x0101021b, "versionName" => 0x0101021c, "targetSdkVersion" => 0x01010270,
		"glEsVersion" => 0x01010281, "required" => 0x0101028e, "extractNativeLibs" => 0x010104ea,
	];

	// an element: its name, attributes (android: ones by name in IDS, others
	// without a namespace), children
	public static function el(name:String, attrs:Array<Attr>, ?children:Array<Element>):Element
		return {name: name, attrs: attrs, children: children ?? []};

	public static function encode(root:Element):Bytes {
		// the strings: the android: attribute names first (the resource map's order)
		var strings:Array<String> = [], index = new Map<String, Int>(), ids:Array<Int> = [];
		function walkNames(e:Element) {
			for (a in e.attrs)
				if (a.android && !index.exists(a.name)) {
					var id = IDS.get(a.name);
					if (id == null) throw "Axml: no resource id for android:" + a.name;
					index.set(a.name, strings.length);
					strings.push(a.name);
					ids.push(id);
				}
			for (c in e.children)
				walkNames(c);
		}
		walkNames(root);
		function str(s:String):Int {
			var i = index.get(s);
			if (i == null) {
				i = strings.length;
				index.set(s, i);
				strings.push(s);
			}
			return i;
		}
		var nsPrefix = str("android"), nsUri = str(ANDROID);
		function walkStrings(e:Element) {
			str(e.name);
			for (a in e.attrs) {
				if (!a.android) str(a.name);
				if (a.type == STRING) str(a.string);
			}
			for (c in e.children)
				walkStrings(c);
		}
		walkStrings(root);
		var body = new helder.pack.Buf(4096);
		inline function chunkHeader(b:helder.pack.Buf, type:Int, headerSize:Int, size:Int) {
			b.u16(type);
			b.u16(headerSize);
			b.u32(size);
		}
		// RES_STRING_POOL_TYPE (UTF-16)
		var data = new helder.pack.Buf(4096);
		var offsets = [];
		for (s in strings) {
			offsets.push(data.len);
			var units = utf16(s);
			data.u16(units.length);
			for (u in units)
				data.u16(u);
			data.u16(0);
		}
		data.align(4);
		var poolHeader = 28, poolSize = poolHeader + 4 * strings.length + data.len;
		chunkHeader(body, 0x0001, poolHeader, poolSize);
		body.u32(strings.length);
		body.u32(0); // styles
		body.u32(0); // flags (UTF-16, not sorted)
		body.u32(poolHeader + 4 * strings.length);
		body.u32(0);
		for (o in offsets)
			body.u32(o);
		body.buf(data);
		// RES_XML_RESOURCE_MAP_TYPE
		chunkHeader(body, 0x0180, 8, 8 + 4 * ids.length);
		for (id in ids)
			body.u32(id);
		// the namespace, the elements
		var line = 1;
		chunkHeader(body, 0x0100, 16, 24); // RES_XML_START_NAMESPACE_TYPE
		body.u32(line);
		body.u32(-1);
		body.u32(nsPrefix);
		body.u32(nsUri);
		function element(e:Element) {
			line++;
			// (attributes ordered by resource id, as aapt2 writes them; the others after)
			var attrs = e.attrs.copy();
			attrs.sort((a, b) -> {
				var x = a.android ? IDS.get(a.name) : 0x7fffffff, y = b.android ? IDS.get(b.name) : 0x7fffffff;
				x < y ? -1 : x > y ? 1 : 0;
			});
			chunkHeader(body, 0x0102, 16, 36 + 20 * attrs.length); // RES_XML_START_ELEMENT_TYPE
			body.u32(line);
			body.u32(-1);
			body.u32(-1); // ns
			body.u32(str(e.name));
			body.u16(20); // attributeStart
			body.u16(20); // attributeSize
			body.u16(attrs.length);
			body.u16(0); // idIndex
			body.u16(0); // classIndex
			body.u16(0); // styleIndex
			for (a in attrs) {
				body.u32(a.android ? nsUri : -1);
				body.u32(str(a.name));
				body.u32(a.type == STRING ? str(a.string) : -1);
				body.u16(8);
				body.u8(0);
				body.u8(a.type);
				body.u32(a.type == STRING ? str(a.string) : a.value);
			}
			for (c in e.children)
				element(c);
			line++;
			chunkHeader(body, 0x0103, 16, 24); // RES_XML_END_ELEMENT_TYPE
			body.u32(line);
			body.u32(-1);
			body.u32(-1);
			body.u32(str(e.name));
		}
		element(root);
		chunkHeader(body, 0x0101, 16, 24); // RES_XML_END_NAMESPACE_TYPE
		body.u32(line + 1);
		body.u32(-1);
		body.u32(nsPrefix);
		body.u32(nsUri);
		var out = new helder.pack.Buf(body.len + 8);
		chunkHeader(out, 0x0003, 8, body.len + 8); // RES_XML_TYPE
		out.buf(body);
		return out.toBytes();
	}

	static function utf16(s:String):Array<Int> {
		var r = [];
		for (c in new haxe.iterators.StringIteratorUnicode(s)) {
			if (c >= 0x10000) {
				r.push(0xd800 + ((c - 0x10000) >> 10));
				r.push(0xdc00 + ((c - 0x10000) & 0x3ff));
			} else r.push(c);
		}
		return r;
	}

	// the document as indented text, attributes as name=value (strings
	// quoted, references @0x..., integers as written): a reader for checks
	public static function dump(b:Bytes):String {
		var out = new StringBuf();
		inline function u16(at:Int)
			return b.getUInt16(at);
		inline function u32(at:Int)
			return b.getInt32(at);
		if (u16(0) != 0x0003) throw "Axml: not binary XML";
		var strings = [], ids = [];
		var at = u16(2), depth = 0;
		while (at < b.length) {
			var type = u16(at), header = u16(at + 2), size = u32(at + 4);
			switch type {
				case 0x0001:
					var n = u32(at + 8), flags = u32(at + 16), start = u32(at + 20);
					for (k in 0...n) {
						var o = at + start + u32(at + header + 4 * k);
						if (flags & 0x100 != 0) {
							var bl = b.get(o + 1) & 0x80 != 0 ? 2 : 1;
							var len = b.get(o + bl);
							strings.push(b.getString(o + bl + 1, len));
						} else {
							var len = u16(o), s = new StringBuf();
							for (i in 0...len)
								s.addChar(u16(o + 2 + 2 * i));
							strings.push(s.toString());
						}
					}
				case 0x0180:
					for (k in 0...((size - 8) >> 2))
						ids.push(u32(at + 8 + 4 * k));
				case 0x0102:
					var name = strings[u32(at + 20)], count = u16(at + 28);
					out.add(StringTools.lpad("", " ", 2 * depth) + "<" + name);
					for (k in 0...count) {
						var a = at + 36 + 20 * k;
						var ns = u32(a), an = u32(a + 4), raw = u32(a + 8), dt = b.get(a + 15), v = u32(a + 16);
						var n = (ns >= 0 ? "android:" : "") + strings[an] + (an < ids.length ? "(0x" + StringTools.hex(ids[an], 8).toLowerCase() + ")" : "");
						var val = switch dt {
							case STRING: '"' + strings[v] + '"';
							case REFERENCE: "@0x" + StringTools.hex(v, 8).toLowerCase();
							case INT_HEX: "0x" + StringTools.hex(v).toLowerCase();
							case BOOLEAN: v != 0 ? "true" : "false";
							case _: Std.string(v);
						}
						out.add(" " + n + "=" + val);
					}
					out.add(">\n");
					depth++;
				case 0x0103:
					depth--;
				case _:
			}
			at += size;
		}
		return out.toString();
	}
}

typedef Element = {name:String, attrs:Array<Attr>, children:Array<Element>};
typedef Attr = {android:Bool, name:String, type:Int, ?string:String, ?value:Int};
