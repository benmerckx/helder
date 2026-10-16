package hxmc.text;

import haxe.io.Bytes;

// A TrueType font (an sfnt with glyf outlines; one face of a collection,
// .ttc): its metrics in font units, the character map (formats 4 and 12),
// horizontal advances, kerning pairs (the kern table's format 0) and glyph
// outlines (simple and composite glyphs, as quadratic contours). CFF
// outlines (.otf with 'OTTO') are not read: FontFile.parse throws.
class FontFile {
	public final data:Bytes;
	// unique per parsed face (atlas keys)
	public final id:Int = nextId++;
	static var nextId = 1;
	// where the face's table directory starts (a collection's face)
	final base:Int;
	final tables = new Map<String, Int>();
	final lengths = new Map<String, Int>();

	public var unitsPerEm(default, null) = 1000;
	public var ascender(default, null) = 0;
	public var descender(default, null) = 0; // negative
	public var lineGap(default, null) = 0;
	public var numGlyphs(default, null) = 0;
	public var weight(default, null) = 400; // OS/2 usWeightClass
	public var italic(default, null) = false;
	public var family(default, null) = "";
	public var subfamily(default, null) = "";

	var longLoca = false;
	var numHMetrics = 0;
	var cmap = -1; // the chosen subtable's offset
	var cmapFormat = 0;
	var kernPairs:Null<Map<Int, Int>> = null;
	// format 4 lookups are cached per character
	final glyphCache = new Map<Int, Int>();

	// the face at index of a font file's bytes (a collection has several)
	public static function parse(data:Bytes, index = 0):FontFile
		return new FontFile(data, index);

	// the number of faces in the file (1, or a collection's)
	public static function faceCount(data:Bytes):Int
		return data.length >= 12 && data.getString(0, 4) == "ttcf" ? u32(data, 8) : 1;

	function new(data:Bytes, index:Int) {
		this.data = data;
		var tag = data.getString(0, 4);
		var b = 0;
		if (tag == "ttcf") {
			if (index >= u32(data, 8)) throw "FontFile: no face " + index;
			b = u32(data, 12 + 4 * index);
			tag = data.getString(b, 4);
		}
		if (tag == "OTTO") throw "FontFile: CFF outlines are not supported";
		if (u32(data, b) != 0x00010000 && tag != "true") throw "FontFile: not a TrueType font";
		base = b;
		var n = u16(data, b + 4);
		for (i in 0...n) {
			var r = b + 12 + 16 * i;
			tables.set(data.getString(r, 4), u32(data, r + 8));
			lengths.set(data.getString(r, 4), u32(data, r + 12));
		}
		for (t in ["head", "hhea", "hmtx", "maxp", "cmap", "loca", "glyf"])
			if (!tables.exists(t)) throw "FontFile: no " + t + " table";
		var head = tables.get("head");
		unitsPerEm = u16(data, head + 18);
		longLoca = s16(data, head + 50) != 0;
		var hhea = tables.get("hhea");
		ascender = s16(data, hhea + 4);
		descender = s16(data, hhea + 6);
		lineGap = s16(data, hhea + 8);
		numHMetrics = u16(data, hhea + 34);
		numGlyphs = u16(data, tables.get("maxp") + 4);
		if (tables.exists("OS/2")) {
			var os2 = tables.get("OS/2");
			weight = u16(data, os2 + 4);
			var fsSelection = u16(data, os2 + 62);
			italic = fsSelection & 1 != 0;
			// (USE_TYPO_METRICS)
			if (fsSelection & 0x80 != 0 && lengths.get("OS/2") >= 74) {
				ascender = s16(data, os2 + 68);
				descender = s16(data, os2 + 70);
				lineGap = s16(data, os2 + 72);
			}
		}
		readNames();
		chooseCmap();
		if (italic == false && subfamily.toLowerCase().indexOf("italic") >= 0 || subfamily.toLowerCase().indexOf("oblique") >= 0) italic = true;
	}

	// --- characters and metrics ---

	// the glyph of a Unicode code point (0: none, the .notdef glyph)
	public function glyph(cp:Int):Int {
		var g = glyphCache.get(cp);
		if (g != null) return g;
		g = lookup(cp);
		glyphCache.set(cp, g);
		return g;
	}

	// the horizontal advance of a glyph, in font units
	public function advance(g:Int):Int {
		var hmtx = tables.get("hmtx");
		return u16(data, hmtx + 4 * (g < numHMetrics ? g : numHMetrics - 1));
	}

	// the left side bearing of a glyph, in font units
	public function leftBearing(g:Int):Int {
		var hmtx = tables.get("hmtx");
		return g < numHMetrics ? s16(data, hmtx + 4 * g + 2) : s16(data, hmtx + 4 * numHMetrics + 2 * (g - numHMetrics));
	}

	// the kerning between two glyphs, in font units (the kern table)
	public function kerning(left:Int, right:Int):Int {
		if (kernPairs == null) readKern();
		var k = kernPairs.get((left << 16) | right);
		return k == null ? 0 : k;
	}

	// --- outlines ---

	// the glyph's bounding box in font units (xMin, yMin, xMax, yMax; all 0 when empty)
	public function bounds(g:Int):Array<Int> {
		if (g < 0 || g >= numGlyphs) return [0, 0, 0, 0];
		var start = loca(g), end = loca(g + 1);
		if (end <= start) return [0, 0, 0, 0];
		var p = tables.get("glyf") + start;
		return [s16(data, p + 2), s16(data, p + 4), s16(data, p + 6), s16(data, p + 8)];
	}

	// the glyph's outline in font units, y up: each contour a closed list of
	// segments (a line, or a quadratic curve through a control point)
	public function outline(g:Int, out:Outline, ?transform:Array<Float>) {
		if (g < 0 || g >= numGlyphs) return;
		var start = loca(g), end = loca(g + 1);
		if (end <= start) return; // (an empty glyph: a space)
		var p = tables.get("glyf") + start;
		var contours = s16(data, p);
		var t = transform == null ? [1.0, 0, 0, 1, 0, 0] : transform;
		if (contours >= 0) simple(p, contours, out, t) else composite(p, out, t);
	}

	function simple(p:Int, contours:Int, out:Outline, t:Array<Float>) {
		var ends = [for (i in 0...contours) u16(data, p + 10 + 2 * i)];
		var n = contours == 0 ? 0 : ends[contours - 1] + 1;
		var q = p + 10 + 2 * contours;
		q += 2 + u16(data, q); // (the instructions)
		var flags = new haxe.ds.Vector<Int>(n);
		var i = 0;
		while (i < n) {
			var f = data.get(q++);
			flags[i++] = f;
			if (f & 8 != 0) {
				var r = data.get(q++);
				while (r-- > 0 && i < n)
					flags[i++] = f;
			}
		}
		var xs = new haxe.ds.Vector<Float>(n), ys = new haxe.ds.Vector<Float>(n);
		var v = 0;
		for (i in 0...n) {
			var f = flags[i];
			if (f & 2 != 0) {
				var d = data.get(q++);
				v += f & 16 != 0 ? d : -d;
			} else if (f & 16 == 0) {
				v += s16(data, q);
				q += 2;
			}
			xs[i] = v;
		}
		v = 0;
		for (i in 0...n) {
			var f = flags[i];
			if (f & 4 != 0) {
				var d = data.get(q++);
				v += f & 32 != 0 ? d : -d;
			} else if (f & 32 == 0) {
				v += s16(data, q);
				q += 2;
			}
			ys[i] = v;
		}
		// transformed points
		for (i in 0...n) {
			var x = xs[i], y = ys[i];
			xs[i] = t[0] * x + t[2] * y + t[4];
			ys[i] = t[1] * x + t[3] * y + t[5];
		}
		var s = 0;
		for (c in 0...contours) {
			var e = ends[c];
			var count = e - s + 1;
			if (count >= 2) contour(xs, ys, flags, s, count, out);
			s = e + 1;
		}
	}

	// one contour of on- and off-curve points: implied on-curve points
	// between two off-curve ones
	function contour(xs:haxe.ds.Vector<Float>, ys:haxe.ds.Vector<Float>, flags:haxe.ds.Vector<Int>, s:Int, n:Int, out:Outline) {
		inline function on(i:Int)
			return flags[s + (i % n)] & 1 != 0;
		inline function x(i:Int)
			return xs[s + (i % n)];
		inline function y(i:Int)
			return ys[s + (i % n)];
		// start at an on-curve point (or between two off-curve ones)
		var first = -1;
		for (i in 0...n)
			if (on(i)) {
				first = i;
				break;
			}
		var sx:Float, sy:Float;
		if (first < 0) {
			sx = (x(0) + x(1)) / 2;
			sy = (y(0) + y(1)) / 2;
			first = 0;
		} else {
			sx = x(first);
			sy = y(first);
		}
		out.moveTo(sx, sy);
		var cx = 0.0, cy = 0.0, control = false;
		for (k in 1...n + 1) {
			var i = first + k;
			var px = x(i), py = y(i);
			if (on(i)) {
				if (control) out.quadTo(cx, cy, px, py) else out.lineTo(px, py);
				control = false;
			} else {
				if (control) {
					var mx = (cx + px) / 2, my = (cy + py) / 2;
					out.quadTo(cx, cy, mx, my);
				}
				cx = px;
				cy = py;
				control = true;
			}
		}
		if (control) out.quadTo(cx, cy, sx, sy);
		out.close();
	}

	function composite(p:Int, out:Outline, t:Array<Float>) {
		var q = p + 10;
		while (true) {
			var flags = u16(data, q), g = u16(data, q + 2);
			q += 4;
			var dx = 0.0, dy = 0.0;
			if (flags & 1 != 0) {
				dx = s16(data, q);
				dy = s16(data, q + 2);
				q += 4;
			} else {
				dx = s8(data.get(q));
				dy = s8(data.get(q + 1));
				q += 2;
			}
			var a = 1.0, b = 0.0, c = 0.0, d = 1.0;
			if (flags & 8 != 0) {
				a = d = f2dot14(q);
				q += 2;
			} else if (flags & 0x40 != 0) {
				a = f2dot14(q);
				d = f2dot14(q + 2);
				q += 4;
			} else if (flags & 0x80 != 0) {
				a = f2dot14(q);
				b = f2dot14(q + 2);
				c = f2dot14(q + 4);
				d = f2dot14(q + 6);
				q += 8;
			}
			// (ARGS_ARE_XY_VALUES assumed: point matching is rare)
			var m = [
				t[0] * a + t[2] * b, t[1] * a + t[3] * b, t[0] * c + t[2] * d, t[1] * c + t[3] * d, t[0] * dx + t[2] * dy + t[4],
				t[1] * dx + t[3] * dy + t[5]
			];
			outline(g, out, m);
			if (flags & 0x20 == 0) break;
		}
	}

	inline function f2dot14(p:Int):Float
		return s16(data, p) / 16384;

	inline function loca(g:Int):Int {
		var l = tables.get("loca");
		return longLoca ? u32(data, l + 4 * g) : u16(data, l + 2 * g) * 2;
	}

	// --- tables ---

	function chooseCmap() {
		var c = tables.get("cmap");
		var n = u16(data, c + 2);
		var best = -1, bestScore = -1;
		for (i in 0...n) {
			var r = c + 4 + 8 * i;
			var platform = u16(data, r), encoding = u16(data, r + 2), off = c + u32(data, r + 4);
			var format = u16(data, off);
			// full Unicode (format 12) over the BMP (format 4)
			var score = switch [platform, encoding, format] {
				case [3, 10, 12] | [0, 4, 12] | [0, 6, 12]: 3;
				case [3, 1, 4] | [0, 3, 4] | [0, 1, 4] | [0, 0, 4]: 2;
				case [3, 0, 4]: 1;
				case _: -1;
			}
			if (score > bestScore) {
				bestScore = score;
				best = off;
			}
		}
		if (best < 0) throw "FontFile: no Unicode character map";
		cmap = best;
		cmapFormat = u16(data, best);
	}

	function lookup(cp:Int):Int {
		var c = cmap;
		if (cmapFormat == 12) {
			var groups = u32(data, c + 12);
			var lo = 0, hi = groups - 1;
			while (lo <= hi) {
				var mid = (lo + hi) >> 1, g = c + 16 + 12 * mid;
				var start = u32(data, g), end = u32(data, g + 4);
				if (cp < start) hi = mid - 1 else if (cp > end) lo = mid + 1 else return u32(data, g + 8) + cp - start;
			}
			return 0;
		}
		if (cp > 0xFFFF) return 0;
		var segX2 = u16(data, c + 6);
		var ends = c + 14, starts = ends + segX2 + 2, deltas = starts + segX2, ranges = deltas + segX2;
		var lo = 0, hi = (segX2 >> 1) - 1;
		while (lo <= hi) {
			var mid = (lo + hi) >> 1;
			var end = u16(data, ends + 2 * mid);
			if (cp > end) {
				lo = mid + 1;
				continue;
			}
			var start = u16(data, starts + 2 * mid);
			if (cp < start) {
				hi = mid - 1;
				continue;
			}
			var delta = u16(data, deltas + 2 * mid), range = u16(data, ranges + 2 * mid);
			if (range == 0) return (cp + delta) & 0xFFFF;
			var g = u16(data, ranges + 2 * mid + range + 2 * (cp - start));
			return g == 0 ? 0 : (g + delta) & 0xFFFF;
		}
		return 0;
	}

	function readKern() {
		kernPairs = new Map();
		if (!tables.exists("kern")) return;
		var k = tables.get("kern");
		if (u16(data, k) != 0) return; // (Apple's version 1 table: not read)
		var n = u16(data, k + 2), p = k + 4;
		for (_ in 0...n) {
			var len = u16(data, p + 2), coverage = u16(data, p + 4);
			// format 0, horizontal, not minimum or cross-stream
			if (coverage >> 8 == 0 && coverage & 7 == 1) {
				var pairs = u16(data, p + 6);
				for (i in 0...pairs) {
					var r = p + 14 + 6 * i;
					kernPairs.set((u16(data, r) << 16) | u16(data, r + 2), s16(data, r + 4));
				}
			}
			p += len;
		}
	}

	function readNames() {
		if (!tables.exists("name")) return;
		var t = tables.get("name");
		var count = u16(data, t + 2), strings = t + u16(data, t + 4);
		var fam = new Map<Int, String>(), sub = new Map<Int, String>();
		for (i in 0...count) {
			var r = t + 6 + 12 * i;
			var platform = u16(data, r), encoding = u16(data, r + 2), language = u16(data, r + 4), id = u16(data, r + 6);
			if (id != 1 && id != 2 && id != 16 && id != 17) continue;
			var len = u16(data, r + 8), off = strings + u16(data, r + 10);
			var s:String = null;
			if (platform == 3 && (encoding == 1 || encoding == 10) && (language == 0x409 || !fam.exists(id + 100))) s = utf16be(off, len);
			else if (platform == 1 && encoding == 0) s = data.getString(off, len);
			else if (platform == 0) s = utf16be(off, len);
			if (s == null) continue;
			// (English, Windows' names first)
			var rank = platform == 3 && language == 0x409 ? 3 : platform == 3 ? 2 : platform == 0 ? 1 : 0;
			var key = id * 10 + rank;
			if (id == 1 || id == 16) fam.set(key, s) else sub.set(key, s);
		}
		function best(m:Map<Int, String>, ids:Array<Int>):String {
			for (id in ids)
				for (rank in [3, 2, 1, 0])
					if (m.exists(id * 10 + rank)) return m.get(id * 10 + rank);
			return "";
		}
		family = best(fam, [16, 1]);
		subfamily = best(sub, [17, 2]);
	}

	function utf16be(off:Int, len:Int):String {
		var b = new StringBuf();
		var i = 0;
		while (i + 1 < len) {
			var c = u16(data, off + i);
			i += 2;
			if (c >= 0xD800 && c < 0xDC00 && i + 1 < len) {
				var d = u16(data, off + i);
				i += 2;
				c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
			}
			b.addChar(c);
		}
		return b.toString();
	}

	public function toString():String
		return '$family $subfamily ($weight' + (italic ? ", italic" : "") + ")";

	static inline function u16(b:Bytes, p:Int):Int
		return (b.get(p) << 8) | b.get(p + 1);

	static inline function s16(b:Bytes, p:Int):Int {
		var v = u16(b, p);
		return v >= 0x8000 ? v - 0x10000 : v;
	}

	static inline function u32(b:Bytes, p:Int):Int
		return (b.get(p) << 24) | (b.get(p + 1) << 16) | (b.get(p + 2) << 8) | b.get(p + 3);

	static inline function s8(v:Int):Int
		return v >= 128 ? v - 256 : v;
}
