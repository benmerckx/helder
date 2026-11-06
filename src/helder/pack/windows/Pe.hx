package helder.pack.windows;

import haxe.io.Bytes;
import helder.pack.Buf;

// A Windows executable (PE32+, hxmc's linker's) made into what a release
// ships, without the SDK's tools (rc, link, editbin): its subsystem
// (Windows' GUI: no console window opened beside it), a resource section
// (.rsrc, appended as a section of its own: the icon in every size,
// RT_ICON and RT_GROUP_ICON, Explorer's, the taskbar's and Alt-Tab's; the
// version information, RT_VERSION, the file's Properties > Details), and
// its checksum (the optional header's, as imagehlp's CheckSumMappedFile
// computes it). Authenticode signs the result.
class Pe {
	public final data:Bytes;
	// e_lfanew's: the COFF header, the optional header, the section table
	public final coff:Int;
	public final opt:Int;
	public final sections:Int;
	public final count:Int;

	public function new(data:Bytes) {
		this.data = data;
		if (data.length < 64 || data.getUInt16(0) != 0x5a4d) throw "Pe: not an executable (no MZ)";
		var pe = data.getInt32(60);
		if (data.getInt32(pe) != 0x4550) throw "Pe: no PE signature";
		coff = pe + 4;
		opt = coff + 20;
		if (data.getUInt16(opt) != 0x20b) throw "Pe: not PE32+ (a 64-bit executable)";
		count = data.getUInt16(coff + 2);
		sections = opt + data.getUInt16(coff + 16);
	}

	public var sectionAlignment(get, never):Int;

	inline function get_sectionAlignment()
		return data.getInt32(opt + 32);

	public var fileAlignment(get, never):Int;

	inline function get_fileAlignment()
		return data.getInt32(opt + 36);

	public var sizeOfHeaders(get, never):Int;

	inline function get_sizeOfHeaders()
		return data.getInt32(opt + 60);

	// where the checksum and the data directories are (PE32+)
	public var checksumAt(get, never):Int;

	inline function get_checksumAt()
		return opt + 64;

	public inline function directoryAt(k:Int):Int
		return opt + 112 + 8 * k;

	public var subsystem(get, never):Int;

	inline function get_subsystem()
		return data.getUInt16(opt + 68);

	// the security directory (Authenticode's certificate table): its file offset and size
	public function certificates():{at:Int, size:Int}
		return {at: data.getInt32(directoryAt(4)), size: data.getInt32(directoryAt(4) + 4)};

	// a section's header fields
	public function section(i:Int):{name:String, vsize:Int, va:Int, rawSize:Int, rawAt:Int} {
		var at = sections + 40 * i;
		var n = data.getString(at, 8);
		var z = n.indexOf(String.fromCharCode(0));
		return {
			name: z < 0 ? n : n.substr(0, z),
			vsize: data.getInt32(at + 8),
			va: data.getInt32(at + 12),
			rawSize: data.getInt32(at + 16),
			rawAt: data.getInt32(at + 20)
		};
	}

	// the executable with the GUI subsystem (2; the console's is 3)
	public static function gui(exe:Bytes):Bytes {
		var p = new Pe(exe.sub(0, exe.length));
		p.data.setUInt16(p.opt + 68, 2);
		return p.data;
	}

	// the executable with a resource section built at its address (rsrc: its
	// bytes for the section's RVA); an executable that has one already, or no
	// room for another section header, is an error
	public static function withResources(exe:Bytes, rsrc:Int->Bytes):Bytes {
		var p = new Pe(exe);
		if (p.data.getInt32(p.directoryAt(2)) != 0) throw "Pe: the executable has resources already";
		if (p.certificates().size != 0) throw "Pe: the executable is signed: its resources are set before";
		var end = p.sections + 40 * (p.count + 1);
		if (end > p.sizeOfHeaders) throw "Pe: no room for another section header";
		for (i in p.sections + 40 * p.count...end)
			if (exe.get(i) != 0) throw "Pe: the headers' room is not empty";
		var va = 0, rawEnd = 0;
		for (i in 0...p.count) {
			var s = p.section(i);
			va = Std.int(Math.max(va, s.va + Std.int(Math.max(s.vsize, s.rawSize))));
			rawEnd = Std.int(Math.max(rawEnd, s.rawAt + s.rawSize));
		}
		va = align(va, p.sectionAlignment);
		var body = rsrc(va);
		// (after everything in the file: its sections and what follows them, a symbol table)
		var rawAt = align(Std.int(Math.max(rawEnd, exe.length)), p.fileAlignment), rawSize = align(body.length, p.fileAlignment);
		var out = Bytes.alloc(rawAt + rawSize);
		out.fill(0, out.length, 0);
		out.blit(0, exe, 0, exe.length);
		out.blit(rawAt, body, 0, body.length);
		var h = p.sections + 40 * p.count;
		out.blit(h, Bytes.ofString(".rsrc"), 0, 5);
		out.setInt32(h + 8, body.length);
		out.setInt32(h + 12, va);
		out.setInt32(h + 16, rawSize);
		out.setInt32(h + 20, rawAt);
		out.setInt32(h + 36, 0x40000040); // INITIALIZED_DATA | MEM_READ
		out.setUInt16(p.coff + 2, p.count + 1);
		out.setInt32(p.opt + 8, out.getInt32(p.opt + 8) + rawSize); // SizeOfInitializedData
		out.setInt32(p.opt + 56, align(va + body.length, p.sectionAlignment)); // SizeOfImage
		out.setInt32(p.directoryAt(2), va);
		out.setInt32(p.directoryAt(2) + 4, body.length);
		return out;
	}

	// the checksum written (imagehlp's: 16-bit one's complement sums of the
	// file without the field, plus the file's length)
	public static function withChecksum(exe:Bytes):Bytes {
		var p = new Pe(exe);
		var at = p.checksumAt;
		var sum = 0.0;
		var i = 0, n = exe.length;
		while (i + 1 < n) {
			if (i != at && i != at + 2) {
				sum += exe.getUInt16(i);
				if (sum > 0xffff) sum = (sum % 65536) + Math.ffloor(sum / 65536);
			}
			i += 2;
		}
		if (n & 1 == 1) {
			sum += exe.get(n - 1);
			if (sum > 0xffff) sum = (sum % 65536) + Math.ffloor(sum / 65536);
		}
		sum = (sum % 65536) + Math.ffloor(sum / 65536);
		var total = Std.int(sum) + n;
		exe.setInt32(at, total);
		return exe;
	}

	public static inline function align(v:Int, a:Int):Int
		return (v + a - 1) & ~(a - 1);
}

// The resource section's bytes: a tree of type, name and language
// directories (IMAGE_RESOURCE_DIRECTORY, entries by id, ascending), its
// data entries' RVAs (the section's address: va), then the data, each
// 8-byte aligned.
class Resources {
	public static inline var RT_ICON = 3;
	public static inline var RT_GROUP_ICON = 14;
	public static inline var RT_VERSION = 16;
	public static inline var RT_MANIFEST = 24;
	// (English, United States)
	public static inline var LANG = 0x409;

	// resources: {type, id, data}, each a language's (LANG); the section at va
	public static function section(resources:Array<{type:Int, id:Int, data:Bytes}>, va:Int):Bytes {
		var types = [];
		for (r in resources)
			if (!types.contains(r.type)) types.push(r.type);
		types.sort((a, b) -> a - b);
		var byType = [for (t in types) t => [for (r in resources) if (r.type == t) r]];
		for (t in types)
			byType.get(t).sort((a, b) -> a.id - b.id);
		// (the layout: the root, each type's directory, each name's language
		// directory, the data entries, then the data)
		inline function dirSize(n:Int):Int
			return 16 + 8 * n;
		var at = dirSize(types.length);
		var typeAt = new Map<Int, Int>(), langAt = new Map<String, Int>();
		for (t in types) {
			typeAt.set(t, at);
			at += dirSize(byType.get(t).length);
		}
		for (t in types)
			for (r in byType.get(t)) {
				langAt.set(t + ":" + r.id, at);
				at += dirSize(1);
			}
		var entryAt = new Map<String, Int>();
		for (t in types)
			for (r in byType.get(t)) {
				entryAt.set(t + ":" + r.id, at);
				at += 16;
			}
		var dataAt = new Map<String, Int>();
		for (t in types)
			for (r in byType.get(t)) {
				at = Pe.align(at, 8);
				dataAt.set(t + ":" + r.id, at);
				at += r.data.length;
			}
		var b = new Buf(at + 16);
		function dir(ids:Array<{id:Int, at:Int, sub:Bool}>) {
			b.u32(0);
			b.u32(0); // (no time: the same input gives the same bytes)
			b.u16(0);
			b.u16(0);
			b.u16(0); // named entries
			b.u16(ids.length);
			for (e in ids) {
				b.u32(e.id);
				b.u32(e.sub ? (0x80000000 | e.at) : e.at);
			}
		}
		dir([for (t in types) {id: t, at: typeAt.get(t), sub: true}]);
		for (t in types)
			dir([for (r in byType.get(t)) {id: r.id, at: langAt.get(t + ":" + r.id), sub: true}]);
		for (t in types)
			for (r in byType.get(t))
				dir([{id: LANG, at: entryAt.get(t + ":" + r.id), sub: false}]);
		for (t in types)
			for (r in byType.get(t)) {
				b.u32(va + dataAt.get(t + ":" + r.id));
				b.u32(r.data.length);
				b.u32(0); // code page
				b.u32(0);
			}
		for (t in types)
			for (r in byType.get(t)) {
				while (b.len < dataAt.get(t + ":" + r.id))
					b.u8(0);
				b.bytes(r.data);
			}
		return b.toBytes();
	}

	// an icon in several sizes (pixels: RGBA of side px): RT_ICON's images
	// (ids from first: a DIB with its alpha below 256, a PNG at 256, as
	// Windows' own icons) and the RT_GROUP_ICON (id group) that lists them
	public static function icon(sizes:Array<Int>, pixels:Int->Bytes, png:Int->Bytes, group = 1, first = 1):Array<{type:Int, id:Int, data:Bytes}> {
		var out = [], dir = new Buf(6 + 14 * sizes.length);
		dir.u16(0);
		dir.u16(1); // an icon
		dir.u16(sizes.length);
		var id = first;
		for (px in sizes) {
			var image = px >= 256 ? png(px) : dib(pixels(px), px);
			dir.u8(px >= 256 ? 0 : px);
			dir.u8(px >= 256 ? 0 : px);
			dir.u8(0); // colours: true colour
			dir.u8(0);
			dir.u16(1); // planes
			dir.u16(32); // bits a pixel
			dir.u32(image.length);
			dir.u16(id);
			out.push({type: RT_ICON, id: id, data: image});
			id++;
		}
		out.push({type: RT_GROUP_ICON, id: group, data: dir.toBytes()});
		return out;
	}

	// a 32-bit DIB of an icon (BITMAPINFOHEADER, twice the height: the
	// colours bottom-up as BGRA, then the 1-bit AND mask, none: the alpha says)
	public static function dib(rgba:Bytes, px:Int):Bytes {
		var maskRow = ((px + 31) >> 5) * 4;
		var b = new Buf(40 + px * px * 4 + maskRow * px);
		b.u32(40);
		b.u32(px);
		b.u32(px * 2);
		b.u16(1);
		b.u16(32);
		b.u32(0); // BI_RGB
		b.u32(px * px * 4 + maskRow * px);
		b.u32(0);
		b.u32(0);
		b.u32(0);
		b.u32(0);
		var y = px - 1;
		while (y >= 0) {
			for (x in 0...px) {
				var i = (y * px + x) * 4;
				b.u8(rgba.get(i + 2));
				b.u8(rgba.get(i + 1));
				b.u8(rgba.get(i));
				b.u8(rgba.get(i + 3));
			}
			y--;
		}
		for (_ in 0...maskRow * px)
			b.u8(0);
		return b.toBytes();
	}

	// VS_VERSIONINFO (RT_VERSION 1): VS_FIXEDFILEINFO's file and product
	// version (four numbers: "1.2.3" and the build), an application's, and
	// the StringFileInfo's strings in US English, Unicode (040904B0)
	public static function version(numbers:Array<Int>, strings:Array<{key:String, value:String}>):{type:Int, id:Int, data:Bytes} {
		var v = numbers.concat([0, 0, 0, 0]).slice(0, 4);
		var fixed = new Buf(52);
		fixed.u32(0xfeef04bd);
		fixed.u32(0x10000);
		for (_ in 0...2) {
			fixed.u32((v[0] << 16) | v[1]);
			fixed.u32((v[2] << 16) | v[3]);
		}
		fixed.u32(0x3f); // flags' mask
		fixed.u32(0); // flags
		fixed.u32(0x40004); // VOS_NT_WINDOWS32
		fixed.u32(1); // VFT_APP
		fixed.u32(0);
		fixed.u32(0);
		fixed.u32(0);
		var table = node("040904B0", null, false, [for (s in strings) node(s.key, utf16z(s.value), true, [])]);
		var info = node("StringFileInfo", null, true, [table]);
		var translation = new Buf(4);
		translation.u16(LANG);
		translation.u16(1200);
		var vars = node("VarFileInfo", null, true, [node("Translation", translation.toBytes(), false, [])]);
		return {type: RT_VERSION, id: 1, data: node("VS_VERSION_INFO", fixed.toBytes(), false, [info, vars])};
	}

	// (a version resource's node: wLength, wValueLength (a text's in WORDs),
	// wType (1: text), its key in UTF-16 and a NUL, padded to 32 bits, its
	// value, padded, its children)
	static function node(key:String, value:Null<Bytes>, text:Bool, children:Array<Bytes>):Bytes {
		var b = new Buf(256);
		b.u16(0);
		b.u16(value == null ? 0 : text ? value.length >> 1 : value.length);
		b.u16(text ? 1 : 0);
		b.bytes(utf16z(key));
		while (b.len % 4 != 0)
			b.u8(0);
		if (value != null) {
			b.bytes(value);
			while (b.len % 4 != 0)
				b.u8(0);
		}
		for (c in children) {
			b.bytes(c);
			while (b.len % 4 != 0)
				b.u8(0);
		}
		var out = b.toBytes();
		out.setUInt16(0, out.length);
		return out;
	}

	static function utf16z(s:String):Bytes {
		var b = new Buf(s.length * 2 + 2);
		for (c in 0...s.length) {
			var code = StringTools.fastCodeAt(s, c);
			b.u16(code);
		}
		b.u16(0);
		return b.toBytes();
	}
}
