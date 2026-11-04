package helder.pack.ios;

import haxe.io.Bytes;
import helder.pack.ios.Plist.PValue;

// A compiled asset catalog (Assets.car) without Xcode's actool, holding the
// app icon alone, as actool writes an Xcode 15+ single-size icon (one
// 1024 px source) for iOS: the renditions App Store validation asks for
// (iPhone's 60 pt at @2x and @3x, 120 and 180 px; iPad's 76 pt and 83.5 pt
// at @2x, 152 and 167 px; the marketing icon, 1024 px), one MultiSized
// rendition an idiom listing its sizes, and Info.plist's CFBundleIcons
// (and ~ipad's) naming it, with the loose AppIcon60x60@2x.png and
// AppIcon76x76@2x~ipad.png actool writes beside it (helder.cli.Ios).
//
// The format, as viraptor/actool (MIT; https://github.com/viraptor/actool)
// documents it after Alexandre Colucci's reverse engineering
// (https://blog.timac.org/2018/1018-reverse-engineering-the-car-file-format/):
// a BOM store (big-endian: a header, the blocks, a table of their offsets
// and lengths, named variables pointing at blocks; trees of key and value
// blocks) whose blocks are CoreUI's (little-endian):
//   CARHEADER ("RATC": CoreUI's version, the rendition count, the key
//     semantics: 2, keys with an idiom), EXTENDED_METADATA ("META": the
//     deployment target and platform), KEYFORMAT ("tmfk": the attributes
//     a rendition key holds, in order), RENDITIONS (a tree: each key the
//     attributes' values, inlined after the leaf's entries too; each value
//     a CSI, "ISTC": the size, scale, pixel format, layout, name, TLVs and
//     the pixels in a CELM, "MLEC"), FACETKEYS (a tree: the name AppIcon
//     to its element, part and identifier), APPEARANCEKEYS (UIAppearanceAny),
//     BITMAPKEYS (a tree by identifier: the values each attribute takes).
// The pixels are stored uncompressed (CELM compression 0: BGRA,
// flagged opaque (0x8) when they are, as the App Store wants its icon;
// premultiplied, rows padded to 32 bytes), which CoreUI reads at any
// deployment target; actool's LZFSE (KCBC) and deepmap2 are smaller, not
// needed. read parses a catalog back (the checks: ours, and a reference of
// actool's for the structure).
class AssetCatalog {
	public static inline var NAME = "AppIcon";

	// key attributes (KEYFORMAT): appearance, localization, scale, idiom,
	// subtype, dimension 2 (the icon's size index), identifier, element, part
	static final KEYFORMAT = [7, 13, 12, 15, 16, 9, 17, 1, 2];
	static inline var ELEMENT = 85;
	static inline var PART_ICON = 220;
	static inline var PART_MULTISIZE = 218;
	static inline var LAYOUT_IMAGE = 12;
	static inline var LAYOUT_MULTISIZE = 1010;

	// the renditions: idiom (1 phone, 2 pad, 6 marketing), points, scale, size index
	public static final ICONS:Array<{idiom:Int, points:Float, scale:Int, index:Int}> = [
		{idiom: 1, points: 60, scale: 2, index: 4}, {idiom: 1, points: 60, scale: 3, index: 4}, {idiom: 2, points: 76, scale: 2, index: 5},
		{idiom: 2, points: 83.5, scale: 2, index: 6}, {idiom: 6, points: 1024, scale: 1, index: 8}
	];

	// the loose PNGs beside the catalog (CFBundleIconFiles' names): file and pixels
	public static final LOOSE = [{file: "AppIcon60x60@2x.png", px: 120}, {file: "AppIcon76x76@2x~ipad.png", px: 152}];

	// Assets.car of the app icon: icon(px) the RGBA pixels at px x px
	// (opaque), min the deployment target (MinimumOSVersion)
	public static function appIcon(icon:Int->Bytes, min:String):Bytes {
		var id = nameHash(NAME);
		var entries:Array<{key:Bytes, value:Bytes}> = [];
		function key(idiom:Int, scale:Int, index:Int, part:Int):Bytes {
			var k = Bytes.alloc(2 * KEYFORMAT.length);
			for (i => a in KEYFORMAT)
				k.setUInt16(2 * i, switch a {
					case 12: scale;
					case 15: idiom;
					case 9: index;
					case 17: id;
					case 1: ELEMENT;
					case 2: part;
					case _: 0;
				});
			return k;
		}
		var sizes = new Map<Int, Array<{points:Int, index:Int}>>();
		for (r in ICONS) {
			var px = Math.round(r.points * r.scale);
			var name = 'AppIcon${r.points}x${r.points}@${r.scale}x.png';
			entries.push({key: key(r.idiom, r.scale, r.index, PART_ICON), value: image(name, px, r.scale, icon(px))});
			var list = sizes.get(r.idiom) ?? [];
			if (!Lambda.exists(list, s -> s.index == r.index)) list.push({points: Math.floor(r.points), index: r.index});
			sizes.set(r.idiom, list);
		}
		for (idiom => list in sizes)
			entries.push({key: key(idiom, 1, 0, PART_MULTISIZE), value: multisize(list)});
		entries.sort((a, b) -> a.key.compare(b.key));

		var bom = new BomWriter();
		bom.named("CARHEADER", header(entries.length));
		bom.tree("RENDITIONS", entries, 4096, 2 * KEYFORMAT.length);
		var facet = new Buf();
		for (v in [0, 0, 3, 1, ELEMENT, 2, PART_ICON, 17, id])
			facet.u16(v);
		bom.tree("FACETKEYS", [{key: Bytes.ofString(NAME), value: facet.toBytes()}], 4096, -1);
		var any = Bytes.alloc(2);
		bom.tree("APPEARANCEKEYS", [{key: Bytes.ofString("UIAppearanceAny"), value: any}], 4096, -1);
		var kf = new Buf();
		kf.str("tmfk");
		kf.u32(0);
		kf.u32(KEYFORMAT.length);
		for (a in KEYFORMAT)
			kf.u32(a);
		bom.named("KEYFORMAT", kf.toBytes());
		var meta = Bytes.alloc(1028);
		meta.blit(0, Bytes.ofString("META"), 0, 4);
		for (f in [{at: 260, s: min}, {at: 516, s: "ios"}, {at: 772, s: "helder"}])
			meta.blit(f.at, Bytes.ofString(f.s), 0, f.s.length);
		bom.named("EXTENDED_METADATA", meta);
		// (BITMAPKEYS: for the identifier, each attribute's values as a mask;
		// element, part and identifier any)
		var masks = new Buf();
		masks.u32(1);
		masks.u32(0);
		masks.u32(4 + 4 * KEYFORMAT.length);
		masks.u32(KEYFORMAT.length);
		for (i => a in KEYFORMAT) {
			if (a == 1 || a == 2 || a == 17) {
				masks.u32(0xffffffff);
				continue;
			}
			var m = 0;
			for (e in entries) {
				var v = e.key.getUInt16(2 * i);
				if (v < 32) m |= 1 << v;
			}
			masks.u32(m == 0 ? 1 : m);
		}
		bom.rawTree("BITMAPKEYS", [{key: id, value: masks.toBytes()}], 1024);
		return bom.toBytes();
	}

	// Info.plist's keys for the catalog's icon (actool's partial plist)
	public static function plistKeys():Map<String, PValue> {
		inline function names(list:Array<String>)
			return PDict(["CFBundlePrimaryIcon" => PDict(["CFBundleIconFiles" => PArray([for (n in list) PString(n)]), "CFBundleIconName" => PString(NAME)])]);
		return ["CFBundleIcons" => names(["AppIcon60x60"]), "CFBundleIcons~ipad" => names(["AppIcon60x60", "AppIcon76x76"])];
	}

	// actool's name hash (a rendition's identifier): Bernstein's (33, from
	// 0x189d7) over 64 bits, folded to 16 the same way; never 0
	public static function nameHash(name:String):Int {
		var h = haxe.Int64.make(0, 0x189d7), m = haxe.Int64.ofInt(33);
		for (i in 0...name.length)
			h = h * m + haxe.Int64.ofInt(name.charCodeAt(i));
		var c0 = h.low & 0xffff, c1 = h.low >>> 16, c2 = h.high & 0xffff, c3 = h.high >>> 16;
		var r = (c0 * 35937 + c1 * 1089 + c2 * 33 + c3) & 0xffff;
		return r == 0 ? 1 : r;
	}

	static function header(count:Int):Bytes {
		var h = Bytes.alloc(436);
		h.blit(0, Bytes.ofString("RATC"), 0, 4);
		h.setInt32(4, 975); // CoreUI's version (iOS catalogs')
		h.setInt32(8, 17); // storage version
		h.setInt32(16, count);
		var main = "@(#)PROGRAM:CoreUI  PROJECT:CoreUI-975.1\n", tool = "helder.pack.ios.AssetCatalog\n";
		h.blit(20, Bytes.ofString(main), 0, main.length);
		h.blit(148, Bytes.ofString(tool), 0, tool.length);
		h.setInt32(424, 2); // schema version
		h.setInt32(428, 1); // colour space (sRGB)
		h.setInt32(432, 2); // key semantics: with an idiom
		return h;
	}

	// a CSI: the 184-byte header, the TLVs, the rendition's data
	static function csi(name:String, w:Int, h:Int, scale:Int, format:String, layout:Int, colorspace:Int, tlv:Bytes, data:Bytes, flags = 0):Bytes {
		var b = new Buf(184 + tlv.length + data.length);
		b.str("ISTC");
		b.u32(1);
		b.u32(flags); // rendition flags (0x8: opaque)
		b.u32(w);
		b.u32(h);
		b.u32(scale * 100);
		if (format == "") b.u32(0) else b.str(format);
		b.u32(colorspace);
		b.u32(0);
		b.u16(layout);
		b.u16(0);
		var n = Bytes.ofString(name);
		b.bytes(n, 0, n.length < 127 ? n.length : 127);
		b.zeros(168 - b.len);
		b.u32(tlv.length);
		b.u32(1); // one bitmap
		b.u32(0);
		b.u32(data.length);
		b.bytes(tlv);
		b.bytes(data);
		return b.toBytes();
	}

	static function tlv(b:Buf, tag:Int, values:Array<Int>) {
		b.u32(tag);
		b.u32(4 * values.length);
		for (v in values)
			b.u32(v);
	}

	// an icon's rendition: BGRA, premultiplied, its rows padded to 32 bytes, uncompressed
	static function image(name:String, px:Int, scale:Int, rgba:Bytes):Bytes {
		var row = (px * 4 + 31) & ~31;
		var pixels = Bytes.alloc(row * px), opaque = true;
		for (y in 0...px)
			for (x in 0...px) {
				var s = 4 * (y * px + x), d = y * row + 4 * x, a = rgba.get(s + 3);
				inline function pm(v:Int)
					return a == 255 ? v : Math.round(v * a / 255);
				pixels.set(d, pm(rgba.get(s + 2)));
				pixels.set(d + 1, pm(rgba.get(s + 1)));
				pixels.set(d + 2, pm(rgba.get(s)));
				pixels.set(d + 3, a);
				if (a != 255) opaque = false;
			}
		var t = new Buf();
		tlv(t, 0x3e9, [1, 0, 0, px, px]); // slices
		tlv(t, 0x3eb, [1, 0, 0, 0, 0, px, px]); // metrics
		t.u32(0x3ec); // blend mode, opacity 1.0
		t.u32(8);
		t.u32(0);
		t.u32(0x3f800000);
		tlv(t, 0x3ee, [1]); // EXIF orientation
		tlv(t, 0x3ef, [row]); // bytes per row
		var celm = new Buf(16 + pixels.length);
		celm.str("MLEC");
		celm.u32(0);
		celm.u32(0); // uncompressed
		celm.u32(pixels.length);
		celm.bytes(pixels);
		return csi(name, px, px, scale, "BGRA", LAYOUT_IMAGE, 1, t.toBytes(), celm.toBytes(), opaque ? 0x8 : 0);
	}

	// an idiom's MultiSized rendition: its sizes in points, ascending, with their indices
	static function multisize(sizes:Array<{points:Int, index:Int}>):Bytes {
		sizes.sort((a, b) -> a.points - b.points);
		var t = new Buf();
		t.u32(0x3ec);
		t.u32(8);
		t.u32(0);
		t.u32(0);
		tlv(t, 0x3ee, [1]);
		var d = new Buf();
		d.str("SISM");
		d.u32(1);
		d.u32(sizes.length);
		for (s in sizes) {
			d.u32(s.points);
			d.u32(s.points);
			d.u32(s.index);
		}
		return csi(NAME, 0, 0, 0, "", LAYOUT_MULTISIZE, 0, t.toBytes(), d.toBytes());
	}

	// ---- reading back (the checks)

	// a catalog parsed: its named blocks, header, key format, facets and
	// renditions (each key's attributes by number, the CSI's fields, its
	// TLVs by tag, the CELM's compression and the pixels when uncompressed)
	public static function read(car:Bytes):CarInfo {
		var bom = BomReader.read(car);
		var h = bom.named("CARHEADER");
		if (h.getString(0, 4) != "RATC") throw "Assets.car: no CARHEADER (RATC)";
		var kf = bom.named("KEYFORMAT");
		if (kf.getString(0, 4) != "tmfk") throw "Assets.car: no KEYFORMAT (tmfk)";
		var format = [for (i in 0...kf.getInt32(8)) kf.getInt32(12 + 4 * i)];
		var meta = bom.named("EXTENDED_METADATA");
		var renditions = [];
		for (e in bom.tree("RENDITIONS").entries) {
			var key = new Map<Int, Int>();
			for (i => a in format)
				key.set(a, e.key.getUInt16(2 * i));
			var c = e.value;
			if (c.getString(0, 4) != "ISTC") throw "Assets.car: a rendition is not a CSI (ISTC)";
			var tlvLen = c.getInt32(168), dataLen = c.getInt32(180), tlvs = new Map<Int, Bytes>(), at = 184;
			while (at < 184 + tlvLen) {
				var tag = c.getInt32(at), n = c.getInt32(at + 4);
				tlvs.set(tag, c.sub(at + 8, n));
				at += 8 + n;
			}
			var data = c.sub(184 + tlvLen, dataLen);
			var compression = -1, pixels:Null<Bytes> = null;
			if (dataLen >= 16 && data.getString(0, 4) == "MLEC") {
				compression = data.getInt32(8);
				if (compression == 0) pixels = data.sub(16, data.getInt32(12));
			}
			renditions.push({
				key: key,
				name: cstr(c, 40, 128),
				flags: c.getInt32(8),
				width: c.getInt32(12),
				height: c.getInt32(16),
				scale: c.getInt32(20),
				format: c.get(24) == 0 ? "" : c.getString(24, 4),
				layout: c.getUInt16(36),
				tlvs: tlvs,
				data: data,
				compression: compression,
				pixels: pixels
			});
		}
		return {
			blocks: bom.names,
			coreui: h.getInt32(4),
			count: h.getInt32(16),
			keySemantics: h.getInt32(432),
			keyformat: format,
			platform: cstr(meta, 516, 256),
			deployment: cstr(meta, 260, 256),
			facets: [for (e in bom.tree("FACETKEYS").entries) e.key.toString() => e.value],
			renditions: renditions,
			renditionKeySize: bom.tree("RENDITIONS").keySize,
			bitmapKeys: [for (e in bom.tree("BITMAPKEYS").entries) e.raw => e.value]
		};
	}

	static function cstr(b:Bytes, at:Int, max:Int):String {
		var e = at;
		while (e < at + max && b.get(e) != 0)
			e++;
		return b.getString(at, e - at);
	}
}

typedef CarInfo = {
	blocks:Array<String>,
	coreui:Int,
	count:Int,
	keySemantics:Int,
	keyformat:Array<Int>,
	platform:String,
	deployment:String,
	facets:Map<String, Bytes>,
	renditions:Array<Rendition>,
	renditionKeySize:Int,
	bitmapKeys:Map<Int, Bytes>
};

typedef Rendition = {
	key:Map<Int, Int>,
	name:String,
	flags:Int,
	width:Int,
	height:Int,
	scale:Int,
	format:String,
	layout:Int,
	tlvs:Map<Int, Bytes>,
	data:Bytes,
	compression:Int,
	pixels:Null<Bytes>
};

// big-endian, as BOM's
private class Be {
	public static function u32(b:haxe.io.BytesBuffer, v:Int) {
		b.addByte(v >>> 24);
		b.addByte((v >> 16) & 0xff);
		b.addByte((v >> 8) & 0xff);
		b.addByte(v & 0xff);
	}

	public static function u16(b:haxe.io.BytesBuffer, v:Int) {
		b.addByte((v >> 8) & 0xff);
		b.addByte(v & 0xff);
	}

	public static inline function get32(b:Bytes, at:Int):Int
		return (b.get(at) << 24) | (b.get(at + 1) << 16) | (b.get(at + 2) << 8) | b.get(at + 3);

	public static inline function get16(b:Bytes, at:Int):Int
		return (b.get(at) << 8) | b.get(at + 1);
}

// A BOM store: block 0 empty, each block 16-byte aligned, then the
// variables (each a block's index and a name) and the block table (at
// least 256 entries, then an empty free list). A tree: a "tree" header
// block (its root, block size, entry count, key size: the fixed key's, or
// 0xffffffff for variable keys) and one leaf (the entries here fit one):
// is-leaf, count, forward, backward, then each value's and key's block
// index; a fixed-key tree's leaf also holds its keys after the entries.
// A raw-key tree's keys are numbers in the leaf, not blocks.
private class BomWriter {
	final blocks:Array<Bytes> = [Bytes.alloc(0)];
	final vars:Array<{name:String, block:Int}> = [];

	public function new() {}

	function add(b:Bytes):Int {
		blocks.push(b);
		return blocks.length - 1;
	}

	public function named(name:String, b:Bytes)
		vars.push({name: name, block: add(b)});

	function header(root:Int, blockSize:Int, count:Int, flag:Int, keySize:Int):Bytes {
		var b = new haxe.io.BytesBuffer();
		b.addString("tree");
		for (v in [1, root, blockSize, count])
			Be.u32(b, v);
		b.addByte(flag);
		Be.u32(b, keySize);
		Be.u32(b, 0);
		return b.getBytes();
	}

	function leaf(rows:Array<{v:Int, k:Int}>, blockSize:Int, inline_:Array<Bytes>, keySize:Int):Bytes {
		if (12 + 8 * rows.length > blockSize) throw "Assets.car: too many entries for one BOM leaf";
		var b = new haxe.io.BytesBuffer();
		Be.u16(b, 1);
		Be.u16(b, rows.length);
		Be.u32(b, 0);
		Be.u32(b, 0);
		for (r in rows) {
			Be.u32(b, r.v);
			Be.u32(b, r.k);
		}
		if (inline_.length > 0) {
			Be.u32(b, 0);
			for (k in inline_)
				b.add(k);
		}
		var size = blockSize + (keySize > 0 ? rows.length * keySize : 0);
		var out = Bytes.alloc(size > b.length ? size : b.length);
		out.blit(0, b.getBytes(), 0, b.length);
		return out;
	}

	// keySize: the fixed key's length (its keys inlined in the leaf), -1 variable
	public function tree(name:String, entries:Array<{key:Bytes, value:Bytes}>, blockSize:Int, keySize:Int) {
		var rows = [for (e in entries) {v: add(e.value), k: add(e.key)}];
		var root = add(leaf(rows, blockSize, keySize > 0 ? [for (e in entries) e.key] : [], keySize));
		vars.push({name: name, block: add(header(root, blockSize, entries.length, 0, keySize > 0 ? keySize : 0xffffffff))});
	}

	public function rawTree(name:String, entries:Array<{key:Int, value:Bytes}>, blockSize:Int) {
		var rows = [for (e in entries) {v: add(e.value), k: e.key}];
		var root = add(leaf(rows, blockSize, [], 0));
		vars.push({name: name, block: add(header(root, blockSize, entries.length, 1, 0))});
	}

	public function toBytes():Bytes {
		var out = new haxe.io.BytesBuffer(), pos = 32;
		var table = [{off: 0, len: 0}];
		var body = new haxe.io.BytesBuffer();
		inline function pad() {
			while (pos % 16 != 0) {
				body.addByte(0);
				pos++;
			}
		}
		for (i in 1...blocks.length) {
			pad();
			table.push({off: pos, len: blocks[i].length});
			body.add(blocks[i]);
			pos += blocks[i].length;
		}
		while (table.length < 256)
			table.push({off: 0, len: 0});
		var v = new haxe.io.BytesBuffer();
		Be.u32(v, vars.length);
		for (x in vars) {
			Be.u32(v, x.block);
			v.addByte(x.name.length);
			v.addString(x.name);
		}
		var vb = v.getBytes();
		pad();
		var varsAt = pos;
		body.add(vb);
		pos += vb.length;
		pad();
		var index = new haxe.io.BytesBuffer();
		Be.u32(index, table.length);
		for (t in table) {
			Be.u32(index, t.off);
			Be.u32(index, t.len);
		}
		for (_ in 0...20)
			index.addByte(0);
		var ib = index.getBytes();
		out.addString("BOMStore");
		for (x in [1, blocks.length, pos, ib.length, varsAt, vb.length])
			Be.u32(out, x);
		out.add(body.getBytes());
		out.add(ib);
		return out.getBytes();
	}
}

private class BomReader {
	public final names:Array<String> = [];

	final b:Bytes;
	final table:Array<{off:Int, len:Int}> = [];
	final vars = new Map<String, Int>();

	function new(b:Bytes) {
		this.b = b;
	}

	public static function read(b:Bytes):BomReader {
		if (b.length < 32 || b.getString(0, 8) != "BOMStore") throw "Assets.car: not a BOM store";
		var r = new BomReader(b);
		var indexAt = Be.get32(b, 16), varsAt = Be.get32(b, 24);
		for (i in 0...Be.get32(b, indexAt))
			r.table.push({off: Be.get32(b, indexAt + 4 + 8 * i), len: Be.get32(b, indexAt + 8 + 8 * i)});
		var at = varsAt + 4;
		for (_ in 0...Be.get32(b, varsAt)) {
			var block = Be.get32(b, at), n = b.get(at + 4);
			var name = b.getString(at + 5, n);
			r.vars.set(name, block);
			r.names.push(name);
			at += 5 + n;
		}
		return r;
	}

	public function block(i:Int):Bytes {
		var t = table[i];
		return b.sub(t.off, t.len);
	}

	public function named(name:String):Bytes {
		if (!vars.exists(name)) throw 'Assets.car: no $name';
		return block(vars.get(name));
	}

	// a tree's entries (raw: a raw-key tree's key as a number), leaf by leaf (forward links)
	public function tree(name:String):{keySize:Int, entries:Array<{key:Bytes, raw:Int, value:Bytes}>} {
		var t = named(name);
		if (t.getString(0, 4) != "tree") throw 'Assets.car: $name is not a tree';
		var raw = t.get(20) == 1, keySize = Be.get32(t, 21), out = [];
		var node = Be.get32(t, 8);
		// (an internal node: down its first child)
		while (Be.get16(block(node), 0) == 0)
			node = Be.get32(block(node), 12);
		while (node != 0) {
			var n = block(node);
			for (i in 0...Be.get16(n, 2)) {
				var v = Be.get32(n, 12 + 8 * i), k = Be.get32(n, 16 + 8 * i);
				out.push({key: raw ? null : block(k), raw: raw ? k : -1, value: block(v)});
			}
			node = Be.get32(n, 4);
		}
		return {keySize: keySize, entries: out};
	}
}
