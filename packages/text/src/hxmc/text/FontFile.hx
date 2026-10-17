package hxmc.text;

import haxe.io.Bytes;

// An OpenType font (an sfnt; one face of a collection, .ttc): its metrics
// in font units, the character map (formats 4 and 12), horizontal
// advances, kerning (GPOS's pair adjustments for the kern feature, else
// the kern table's format 0 pairs) and glyph outlines:
// TrueType's (glyf: simple and composite glyphs, as quadratic contours) or
// CFF's ('OTTO', .otf: Cff, cubic curves). CFF2 (variable) outlines are
// not read: FontFile.parse throws.
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
	// GPOS's kern lookups' pair adjustment subtables (null: not read; empty: none)
	var pairPos:Null<Array<Int>> = null;
	final kernCache = new Map<Int, Int>();
	// the tables read per glyph
	var hmtx = 0;
	var glyf = 0;
	var locaAt = 0;
	// the CFF outlines (null: glyf's)
	var cff:Null<Cff> = null;
	// cmap lookups cached per character: pages of 256 (-1: not looked up)
	final glyphPages:Array<haxe.ds.Vector<Int>> = [];

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
		if (u32(data, b) != 0x00010000 && tag != "true" && tag != "OTTO") throw "FontFile: not an OpenType font";
		base = b;
		var n = u16(data, b + 4);
		for (i in 0...n) {
			var r = b + 12 + 16 * i;
			tables.set(data.getString(r, 4), u32(data, r + 8));
			lengths.set(data.getString(r, 4), u32(data, r + 12));
		}
		var outlines = tag == "OTTO" ? ["CFF "] : ["loca", "glyf"];
		if (tag == "OTTO" && !tables.exists("CFF ") && tables.exists("CFF2")) throw "FontFile: CFF2 outlines are not supported";
		for (t in ["head", "hhea", "hmtx", "maxp", "cmap"].concat(outlines))
			if (!tables.exists(t)) throw "FontFile: no " + t + " table";
		hmtx = tables.get("hmtx");
		var head = tables.get("head");
		unitsPerEm = u16(data, head + 18);
		if (tag == "OTTO") cff = new Cff(data, tables.get("CFF "), unitsPerEm) else {
			glyf = tables.get("glyf");
			locaAt = tables.get("loca");
		}
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
		var p = cp >> 8;
		if (p < 0 || p > 0x10FF) return 0;
		while (glyphPages.length <= p)
			glyphPages.push(null);
		var page = glyphPages[p];
		if (page == null) {
			page = new haxe.ds.Vector(256, -1);
			glyphPages[p] = page;
		}
		var g = page[cp & 255];
		if (g < 0) {
			g = lookup(cp);
			page[cp & 255] = g;
		}
		return g;
	}

	// the horizontal advance of a glyph, in font units
	public function advance(g:Int):Int {
		return u16(data, hmtx + 4 * (g < numHMetrics ? g : numHMetrics - 1));
	}

	// the left side bearing of a glyph, in font units
	public function leftBearing(g:Int):Int {
		return g < numHMetrics ? s16(data, hmtx + 4 * g + 2) : s16(data, hmtx + 4 * numHMetrics + 2 * (g - numHMetrics));
	}

	// the kerning between two glyphs, in font units: GPOS's kern feature
	// (pair adjustments: the first glyph's advance), else the kern table
	public function kerning(left:Int, right:Int):Int {
		if (pairPos == null) readGpos();
		var key = (left << 16) | right;
		if (pairPos.length > 0) {
			var c = kernCache.get(key);
			if (c == null) {
				c = 0;
				// (each lookup: its first subtable that covers the pair)
				var i = 0;
				while (i < pairPos.length) {
					var end = pairPos[i];
					i++;
					while (i < end) {
						var v = pairAdjustment(pairPos[i], left, right);
						i++;
						if (v != NONE) {
							c += v;
							i = end;
						}
					}
				}
				kernCache.set(key, c);
			}
			return c;
		}
		if (kernPairs == null) readKern();
		var k = kernPairs.get(key);
		return k == null ? 0 : k;
	}

	static inline var NONE = 0x7FFFFFFF;

	// GPOS: the subtables of the lookups the kern feature uses (pair
	// adjustment, type 2; in an extension, type 9), as runs: each lookup's
	// end index, then its subtables' offsets
	function readGpos() {
		pairPos = [];
		if (!tables.exists("GPOS")) return;
		var g = tables.get("GPOS");
		var features = g + u16(data, g + 6), lookups = g + u16(data, g + 8);
		var used = new Map<Int, Bool>();
		for (i in 0...u16(data, features)) {
			var r = features + 2 + 6 * i;
			if (data.getString(r, 4) != "kern") continue;
			var f = features + u16(data, r + 4);
			for (k in 0...u16(data, f + 2))
				used.set(u16(data, f + 4 + 2 * k), true);
		}
		var order = [for (k in used.keys()) k];
		order.sort(Reflect.compare);
		for (l in order) {
			if (l >= u16(data, lookups)) continue;
			var t = lookups + u16(data, lookups + 2 + 2 * l);
			var type = u16(data, t);
			var at = pairPos.length;
			pairPos.push(0);
			for (s in 0...u16(data, t + 4)) {
				var st = t + u16(data, t + 6 + 2 * s);
				var stType = type;
				if (type == 9) {
					stType = u16(data, st + 2);
					st += u32(data, st + 4);
				}
				if (stType == 2) pairPos.push(st);
			}
			if (pairPos.length == at + 1) pairPos.pop() else pairPos[at] = pairPos.length;
		}
	}

	// --- GSUB ---

	// the GSUB lookups of a feature for a script (its default language
	// system, else DFLT's), in the lookup list's order
	public function gsubLookups(script:String, feature:String):Array<Int>
		return featureLookups("GSUB", script, feature);

	// the same in GPOS
	public function gposLookups(script:String, feature:String):Array<Int>
		return featureLookups("GPOS", script, feature);

	function featureLookups(table:String, script:String, feature:String):Array<Int> {
		var key = table + "/" + script + "/" + feature;
		var cached = gsubCache.get(key);
		if (cached != null) return cached;
		var out:Array<Int> = [];
		gsubCache.set(key, out);
		if (!tables.exists(table)) return out;
		var g = tables.get(table);
		var scripts = g + u16(data, g + 4), features = g + u16(data, g + 6);
		var langSys = -1;
		for (want in [script, "DFLT"]) {
			for (i in 0...u16(data, scripts)) {
				var r = scripts + 2 + 6 * i;
				if (data.getString(r, 4) != want) continue;
				var st = scripts + u16(data, r + 4);
				if (u16(data, st) != 0) langSys = st + u16(data, st);
			}
			if (langSys >= 0) break;
		}
		if (langSys < 0) return out;
		for (k in 0...u16(data, langSys + 4)) {
			var fi = u16(data, langSys + 6 + 2 * k), r = features + 2 + 6 * fi;
			if (data.getString(r, 4) != feature) continue;
			var ft = features + u16(data, r + 4);
			for (j in 0...u16(data, ft + 2))
				out.push(u16(data, ft + 4 + 2 * j));
		}
		out.sort(Reflect.compare);
		return out;
	}

	final gsubCache = new Map<String, Array<Int>>();

	// a GSUB lookup's subtables (offsets) and type, extensions unwrapped
	inline function gsubSubtables(lookup:Int):{type:Int, flag:Int, subtables:Array<Int>}
		return subtables("GSUB", lookup, 7);

	// a lookup's subtables in a table (GSUB, GPOS: its extension type)
	function subtables(table:String, lookup:Int, extension:Int):{type:Int, flag:Int, subtables:Array<Int>} {
		var cache = extension == 9 ? gposSubtables : gsubSubtableCache;
		var c = cache.get(lookup);
		if (c != null) return c;
		var r = readSubtables(table, lookup, extension);
		cache.set(lookup, r);
		return r;
	}

	final gposSubtables = new Map<Int, {type:Int, flag:Int, subtables:Array<Int>}>();
	final gsubSubtableCache = new Map<Int, {type:Int, flag:Int, subtables:Array<Int>}>();

	function readSubtables(table:String, lookup:Int, extension:Int):{type:Int, flag:Int, subtables:Array<Int>} {
		var g = tables.get(table), list = g + u16(data, g + 8);
		var t = list + u16(data, list + 2 + 2 * lookup);
		var type = u16(data, t), flag = u16(data, t + 2), out = [];
		var ext = type == extension;
		for (s in 0...u16(data, t + 4)) {
			var st = t + u16(data, t + 6 + 2 * s);
			if (ext) {
				type = u16(data, st + 2);
				st += u32(data, st + 4);
			}
			out.push(st);
		}
		return {type: type, flag: flag, subtables: out};
	}

	// a single substitution lookup's glyph for g (g: not covered)
	public function substitute(lookup:Int, g:Int):Int {
		var l = gsubSubtables(lookup);
		if (l.type != 1) return g;
		for (st in l.subtables) {
			var ci = coverage(st + u16(data, st + 2), g);
			if (ci < 0) continue;
			return u16(data, st) == 1 ? (g + s16(data, st + 4)) & 0xFFFF : u16(data, st + 6 + 2 * ci);
		}
		return g;
	}

	// a ligature substitution lookup's ligature starting at gs[at]: its glyph
	// and how many glyphs it takes (count 0: none)
	public function ligature(lookup:Int, gs:Array<Int>, at:Int):{glyph:Int, count:Int} {
		var l = gsubSubtables(lookup);
		if (l.type == 4)
			for (st in l.subtables) {
				var ci = coverage(st + u16(data, st + 2), gs[at]);
				if (ci < 0) continue;
				var set = st + u16(data, st + 6 + 2 * ci);
				for (k in 0...u16(data, set)) {
					var lig = set + u16(data, set + 2 + 2 * k);
					var n = u16(data, lig + 2), ok = at + n <= gs.length;
					var j = 1;
					while (ok && j < n) {
						if (gs[at + j] != u16(data, lig + 4 + 2 * (j - 1))) ok = false;
						j++;
					}
					if (ok) return {glyph: u16(data, lig), count: n};
				}
			}
		return {glyph: 0, count: 0};
	}

	// --- GPOS's marks ---

	// GDEF's class of a glyph: 1 base, 2 ligature, 3 mark, 4 component (0: unclassed, or no GDEF)
	public function glyphClass(g:Int):Int {
		if (gdefClasses == -2) {
			gdefClasses = -1;
			if (tables.exists("GDEF")) {
				var d = tables.get("GDEF"), o = u16(data, d + 4);
				if (o != 0) gdefClasses = d + o;
			}
		}
		return gdefClasses < 0 ? 0 : classOf(gdefClasses, g);
	}

	var gdefClasses = -2;

	public var hasGlyphClasses(get, never):Bool;

	function get_hasGlyphClasses():Bool {
		glyphClass(0);
		return gdefClasses >= 0;
	}

	// the lookups of the features mark and mkmk for a script, in the lookup list's order
	public function markLookups(script:String):Array<Int> {
		var cached = markCache.get(script);
		if (cached != null) return cached;
		var out = gposLookups(script, "mark").concat(gposLookups(script, "mkmk"));
		out.sort(Reflect.compare);
		markCache.set(script, out);
		return out;
	}

	final markCache = new Map<String, Array<Int>>();

	// a mark attachment lookup's place for a mark: the offset (font units) from
	// the glyph it attaches to (base: a base glyph, or a ligature with its
	// component; prev: the mark before it) to the mark's origin, and whether
	// it attaches to prev (null: the lookup does not apply)
	public function markAttachment(lookup:Int, base:Int, component:Int, prev:Int, mark:Int):Null<{x:Int, y:Int, toPrev:Bool}> {
		var l = subtables("GPOS", lookup, 9);
		if (l.type < 4 || l.type > 6) return null;
		for (st in l.subtables) {
			if (u16(data, st) != 1) continue;
			var to = l.type == 6 ? prev : base;
			if (to < 0) continue;
			var mi = coverage(st + u16(data, st + 2), mark);
			if (mi < 0) continue;
			var bi = coverage(st + u16(data, st + 4), to);
			if (bi < 0) continue;
			var classes = u16(data, st + 6);
			var marks = st + u16(data, st + 8), bases = st + u16(data, st + 10);
			if (mi >= u16(data, marks) || bi >= u16(data, bases)) continue;
			var mr = marks + 2 + 4 * mi;
			var cls = u16(data, mr), ma = marks + u16(data, mr + 2);
			if (cls >= classes) continue;
			var anchor = 0;
			if (l.type == 5) {
				// (a ligature: its components' anchors, the last one for a component past them)
				var attach = bases + u16(data, bases + 2 + 2 * bi);
				var count = u16(data, attach);
				if (count == 0) continue;
				var c = component < 0 || component >= count ? count - 1 : component;
				var o = u16(data, attach + 2 + 2 * (c * classes + cls));
				if (o != 0) anchor = attach + o;
			} else {
				var o = u16(data, bases + 2 + 2 * (bi * classes + cls));
				if (o != 0) anchor = bases + o;
			}
			if (anchor == 0) continue;
			return {x: s16(data, anchor + 2) - s16(data, ma + 2), y: s16(data, anchor + 4) - s16(data, ma + 4), toPrev: l.type == 6};
		}
		return null;
	}

	// a pair adjustment subtable's change to the first glyph's advance (NONE: it does not cover the pair)
	function pairAdjustment(st:Int, left:Int, right:Int):Int {
		var ci = coverage(st + u16(data, st + 2), left);
		if (ci < 0) return NONE;
		var f1 = u16(data, st + 4), f2 = u16(data, st + 6);
		var s1 = valueSize(f1), s2 = valueSize(f2);
		if (u16(data, st) == 1) {
			if (ci >= u16(data, st + 8)) return NONE;
			var set = st + u16(data, st + 10 + 2 * ci);
			var n = u16(data, set), rec = 2 + s1 + s2;
			var lo = 0, hi = n - 1;
			while (lo <= hi) {
				var mid = (lo + hi) >> 1, r = set + 2 + rec * mid;
				var g = u16(data, r);
				if (g < right) lo = mid + 1 else if (g > right) hi = mid - 1 else return xAdvance(r + 2, f1);
			}
			return NONE;
		}
		if (u16(data, st) != 2) return NONE;
		var c1 = classOf(st + u16(data, st + 8), left), c2 = classOf(st + u16(data, st + 10), right);
		var n1 = u16(data, st + 12), n2 = u16(data, st + 14);
		if (c1 >= n1 || c2 >= n2) return 0;
		return xAdvance(st + 16 + (c1 * n2 + c2) * (s1 + s2), f1);
	}

	// a value record's size (two bytes a field) and its XAdvance (format bit 4: after XPlacement, YPlacement)
	static function valueSize(format:Int):Int {
		var n = 0;
		for (b in 0...8)
			if (format & (1 << b) != 0) n += 2;
		return n;
	}

	function xAdvance(p:Int, format:Int):Int {
		if (format & 4 == 0) return 0;
		return s16(data, p + (format & 1 != 0 ? 2 : 0) + (format & 2 != 0 ? 2 : 0));
	}

	// a coverage table's index of a glyph (-1: not covered)
	function coverage(c:Int, g:Int):Int {
		var n = u16(data, c + 2);
		var lo = 0, hi = n - 1;
		if (u16(data, c) == 1) {
			while (lo <= hi) {
				var mid = (lo + hi) >> 1, v = u16(data, c + 4 + 2 * mid);
				if (v < g) lo = mid + 1 else if (v > g) hi = mid - 1 else return mid;
			}
			return -1;
		}
		while (lo <= hi) {
			var mid = (lo + hi) >> 1, r = c + 4 + 6 * mid;
			if (g < u16(data, r)) hi = mid - 1 else if (g > u16(data, r + 2)) lo = mid + 1 else return u16(data, r + 4) + g - u16(data, r);
		}
		return -1;
	}

	// a class definition table's class of a glyph (0: the rest)
	function classOf(c:Int, g:Int):Int {
		if (u16(data, c) == 1) {
			var start = u16(data, c + 2), n = u16(data, c + 4);
			return g >= start && g < start + n ? u16(data, c + 6 + 2 * (g - start)) : 0;
		}
		var lo = 0, hi = u16(data, c + 2) - 1;
		while (lo <= hi) {
			var mid = (lo + hi) >> 1, r = c + 4 + 6 * mid;
			if (g < u16(data, r)) hi = mid - 1 else if (g > u16(data, r + 2)) lo = mid + 1 else return u16(data, r + 4);
		}
		return 0;
	}

	// --- outlines ---

	// the glyph's bounding box in font units (xMin, yMin, xMax, yMax; all 0 when empty)
	public function bounds(g:Int):Array<Int> {
		if (g < 0 || g >= numGlyphs) return [0, 0, 0, 0];
		if (cff != null) return cff.bounds(g);
		var start = loca(g), end = loca(g + 1);
		if (end <= start) return [0, 0, 0, 0];
		var p = glyf + start;
		return [s16(data, p + 2), s16(data, p + 4), s16(data, p + 6), s16(data, p + 8)];
	}

	// the glyph's outline in font units, y up: each contour a closed list of
	// segments (a line, a quadratic curve through a control point, or CFF's
	// cubic curves through two)
	public function outline(g:Int, out:Outline, ?transform:Array<Float>) {
		if (g < 0 || g >= numGlyphs) return;
		if (cff != null) {
			cff.outline(g, out);
			return;
		}
		var start = loca(g), end = loca(g + 1);
		if (end <= start) return; // (an empty glyph: a space)
		var p = glyf + start;
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
		var l = locaAt;
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
