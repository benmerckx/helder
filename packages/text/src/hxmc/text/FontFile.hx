package hxmc.text;

import haxe.io.Bytes;

// An OpenType font (an sfnt; one face of a collection, .ttc): its metrics
// in font units, the character map (formats 4 and 12), horizontal
// advances, kerning (GPOS's pair adjustments for the kern feature, else
// the kern table's format 0 pairs) and glyph outlines:
// TrueType's (glyf: simple and composite glyphs, as quadratic contours) or
// CFF's ('OTTO', .otf: Cff, cubic curves). A variable TrueType font's
// axes (axes) give instances (instance: gvar's deltas applied to outlines
// and advances; Variations). CFF2 (variable) outlines are not read:
// FontFile.parse throws.
class FontFile {
	public final data:Bytes;
	// unique per parsed face (atlas keys)
	public final id:Int = nextId++;
	static var nextId = 1;
	// where the face's table directory starts (a collection's face)
	final base:Int;
	final index:Int;
	// a variable font's axes and deltas (null: not variable), this instance's
	// normalized coordinates (null: the default instance)
	var vars:Null<Variations> = null;
	var coords:Null<Array<Float>> = null;
	// (an instance's advances, by glyph)
	var variedAdvances:Null<Map<Int, Float>> = null;
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
	// no outlines, colour bitmaps only
	public var bitmapsOnly(default, null) = false;
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
		this.index = index;
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
		// (a font of colour bitmaps only, as Noto Color Emoji: no outlines)
		bitmapsOnly = tag != "OTTO" && !tables.exists("glyf") && (tables.exists("CBDT") && tables.exists("CBLC") || tables.exists("sbix"));
		var outlines = tag == "OTTO" ? ["CFF "] : bitmapsOnly ? [] : ["loca", "glyf"];
		if (tag == "OTTO" && !tables.exists("CFF ") && tables.exists("CFF2")) throw "FontFile: CFF2 outlines are not supported";
		for (t in ["head", "hhea", "hmtx", "maxp", "cmap"].concat(outlines))
			if (!tables.exists(t)) throw "FontFile: no " + t + " table";
		hmtx = tables.get("hmtx");
		var head = tables.get("head");
		unitsPerEm = u16(data, head + 18);
		if (tag == "OTTO") cff = new Cff(data, tables.get("CFF "), unitsPerEm) else if (!bitmapsOnly) {
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
		hasColor = tables.exists("CBLC") && tables.exists("CBDT") || tables.exists("sbix") || tables.exists("COLR") && tables.exists("CPAL");
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
		if (tables.exists("fvar") && glyf != 0)
			vars = new Variations(data, tables.get("fvar"), tables.exists("avar") ? tables.get("avar") : -1, tables.exists("gvar") ? tables.get("gvar") : -1);
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

	// a variable font's axes (empty when it is not): each tag ("wght",
	// "wdth"...), range and default, in the axis's own units
	public var axes(get, never):Array<{tag:String, min:Float, def:Float, max:Float}>;

	inline function get_axes()
		return vars == null ? [] : vars.axes;

	// the instance at values by axis tag (["wght" => 700]; the defaults for
	// the others): a face of its own (its own id), the same data
	public function instance(values:Map<String, Float>):FontFile {
		var f = new FontFile(data, index);
		if (vars == null) return f;
		f.vars = vars;
		f.coords = vars.normalize(values);
		f.variedAdvances = new Map();
		if (values.exists("wght")) f.weight = Std.int(values.get("wght"));
		return f;
	}

	// the horizontal advance of a glyph, in font units (an instance's: with
	// its phantom points' deltas)
	public function advance(g:Int):Float {
		var a:Float = u16(data, hmtx + 4 * (g < numHMetrics ? g : numHMetrics - 1));
		if (coords == null) return a;
		var v = variedAdvances.get(g);
		if (v != null) return v;
		var d = phantom(g);
		v = a + d[1] - d[0];
		variedAdvances.set(g, v);
		return v;
	}

	// (an instance's glyph: its phantom points' x deltas, the origin's and the advance's)
	function phantom(g:Int):Array<Float> {
		var n = 0;
		var start = loca(g), end = loca(g + 1);
		if (end > start) {
			var p = glyf + start, contours = s16(data, p);
			if (contours >= 0) n = contours == 0 ? 0 : u16(data, p + 10 + 2 * (contours - 1)) + 1 else {
				var q = p + 10;
				while (true) {
					var flags = u16(data, q);
					n++;
					q += 4 + (flags & 1 != 0 ? 4 : 2) + (flags & 8 != 0 ? 2 : flags & 0x40 != 0 ? 4 : flags & 0x80 != 0 ? 8 : 0);
					if (flags & 0x20 == 0) break;
				}
			}
		}
		var dx = zeros(n + 4), dy = zeros(n + 4);
		vars.deltas(g, coords, n + 4, null, null, null, dx, dy);
		return [dx[n], dx[n + 1]];
	}

	static function zeros(n:Int):haxe.ds.Vector<Float> {
		var v = new haxe.ds.Vector<Float>(n);
		for (i in 0...n)
			v[i] = 0;
		return v;
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

	// a single substitution lookup's glyph for g (g: not covered); an
	// alternate substitution's nth (from 1; g: not that many)
	public function substitute(lookup:Int, g:Int, nth = 1):Int {
		var l = gsubSubtables(lookup);
		if (l.type != 1 && l.type != 3) return g;
		for (st in l.subtables) {
			var ci = coverage(st + u16(data, st + 2), g);
			if (ci < 0) continue;
			if (l.type == 3) {
				var set = st + u16(data, st + 6 + 2 * ci);
				return nth >= 1 && nth <= u16(data, set) ? u16(data, set + 2 * nth) : g;
			}
			return u16(data, st) == 1 ? (g + s16(data, st + 4)) & 0xFFFF : u16(data, st + 6 + 2 * ci);
		}
		return g;
	}

	// the single and alternate substitution lookups of the features turned
	// on (FontSet.features) for a script, in the lookup list's order, each
	// with its feature's value; kept by script and features
	public function substitutionLookups(script:String, features:Array<FontFeature>, key:String):Array<{lookup:Int, value:Int}> {
		var k = script + "|" + key, l = substCache.get(k);
		if (l != null) return l;
		l = [];
		for (f in features) {
			if (f.value == 0) continue;
			for (i in gsubLookups(script, f.tag)) {
				var t = gsubSubtables(i).type;
				if ((t == 1 || t == 3) && !Lambda.exists(l, e -> e.lookup == i)) l.push({lookup: i, value: f.value});
			}
		}
		l.sort((a, b) -> a.lookup - b.lookup);
		substCache.set(k, l);
		return l;
	}

	final substCache = new Map<String, Array<{lookup:Int, value:Int}>>();

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
		if (gdefClasses < 0) return 0;
		// (each glyph's class looked up once)
		if (g < 0 || g >= numGlyphs) return classOf(gdefClasses, g);
		if (glyphClasses == null) {
			glyphClasses = new haxe.ds.Vector(numGlyphs);
			for (i in 0...numGlyphs)
				glyphClasses[i] = -1;
		}
		var c = glyphClasses[g];
		if (c < 0) c = glyphClasses[g] = classOf(gdefClasses, g);
		return c;
	}

	var glyphClasses:Null<haxe.ds.Vector<Int>> = null;

	// the standard ligatures' lookups for a script (liga and clig, in the lookup list's order)
	public function ligatureLookups(script:String):Array<Int> {
		var l = ligaCache.get(script);
		if (l == null) {
			l = gsubLookups(script, "liga").concat(gsubLookups(script, "clig"));
			l.sort(Reflect.compare);
			ligaCache.set(script, l);
		}
		return l;
	}

	final ligaCache = new Map<String, Array<Int>>();

	// the ligatures' lookups with features asked for (FontSet.features): liga
	// and clig unless turned off, and the ligature lookups of those turned on
	// (dlig, hlig...), in the lookup list's order; kept by script and features
	public function ligatureLookupsWith(script:String, features:Array<FontFeature>, key:String):Array<Int> {
		var k = script + "|" + key, l = ligaCache.get(k);
		if (l != null) return l;
		var off = tag -> Lambda.exists(features, f -> f.tag == tag && f.value == 0);
		l = [];
		for (tag in ["liga", "clig"])
			if (!off(tag)) for (i in gsubLookups(script, tag))
				if (l.indexOf(i) < 0) l.push(i);
		for (f in features)
			if (f.value > 0 && f.tag != "liga" && f.tag != "clig") for (i in gsubLookups(script, f.tag))
				if (gsubSubtables(i).type == 4 && l.indexOf(i) < 0) l.push(i);
		l.sort(Reflect.compare);
		ligaCache.set(k, l);
		return l;
	}

	// the glyphs that begin a ligature of these lookups (their subtables'
	// coverages), a byte by glyph id (1: may begin one); kept by lookups
	public function ligatureStarts(lookups:Array<Int>):haxe.io.Bytes {
		var key = lookups.join(",");
		var b = startsCache.get(key);
		if (b != null) return b;
		b = haxe.io.Bytes.alloc(numGlyphs + 1);
		for (l in lookups) {
			var t = gsubSubtables(l);
			if (t.type != 4) continue;
			for (st in t.subtables) {
				var c = st + u16(data, st + 2), n = u16(data, c + 2);
				if (u16(data, c) == 1)
					for (k in 0...n) {
						var g = u16(data, c + 4 + 2 * k);
						if (g < b.length) b.set(g, 1);
					}
				else
					for (k in 0...n) {
						var r = c + 4 + 6 * k, end = u16(data, r + 2);
						for (g in u16(data, r)...end + 1)
							if (g < b.length) b.set(g, 1);
					}
			}
		}
		startsCache.set(key, b);
		return b;
	}

	final startsCache = new Map<String, haxe.io.Bytes>();

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

	// --- colour glyphs ---

	// whether glyphs have colour: bitmaps (CBDT, sbix) or layers (COLR)
	public var hasColor(default, null) = false;

	// a glyph's colour bitmap for a size in pixels (the strike nearest above,
	// else the largest): a PNG file, its strike's pixels per em, and its
	// place in those pixels (from the glyph's origin: left, top above the
	// baseline; its size); null: none
	public function colorBitmap(g:Int, size:Float):Null<{png:Bytes, ppem:Int, left:Int, top:Int, width:Int, height:Int}> {
		if (tables.exists("CBLC") && tables.exists("CBDT")) return cbdt(g, size, true);
		if (tables.exists("sbix")) return sbix(g, size);
		return null;
	}

	// a glyph's advance at a size, in pixels: a colour bitmap's own (CBDT's
	// metrics, as Skia measures them) in a font of bitmaps only, else hmtx's
	public function advanceAt(g:Int, size:Float):Float {
		if (bitmapsOnly && tables.exists("CBLC")) {
			var b = cbdt(g, size, false);
			if (b != null && b.advance > 0) return b.advance * size / b.ppem;
		}
		return advance(g) * size / unitsPerEm;
	}

	function cbdt(g:Int, size:Float, withPng:Bool):Null<{png:Bytes, ppem:Int, left:Int, top:Int, width:Int, height:Int, advance:Int}> {
		var c = tables.get("CBLC"), d = tables.get("CBDT");
		var n = u32(data, c + 4), best = -1, bestPpem = 0;
		for (i in 0...n) {
			var r = c + 8 + 48 * i;
			if (g < u16(data, r + 40) || g > u16(data, r + 42)) continue;
			var ppem = data.get(r + 45);
			if (best < 0 || (bestPpem < size ? ppem > bestPpem : ppem >= size && ppem < bestPpem)) {
				best = r;
				bestPpem = ppem;
			}
		}
		if (best < 0) return null;
		var array = c + u32(data, best), count = u32(data, best + 8);
		for (k in 0...count) {
			var a = array + 8 * k, first = u16(data, a), last = u16(data, a + 2);
			if (g < first || g > last) continue;
			var sub = array + u32(data, a + 4);
			var indexFormat = u16(data, sub), imageFormat = u16(data, sub + 2), imageData = d + u32(data, sub + 4);
			// (where the glyph's data is, and the metrics the index gives: formats 2 and 5)
			var at = -1, big = -1;
			switch indexFormat {
				case 1:
					var o0 = u32(data, sub + 8 + 4 * (g - first)), o1 = u32(data, sub + 12 + 4 * (g - first));
					if (o1 > o0) at = imageData + o0;
				case 3:
					var o0 = u16(data, sub + 8 + 2 * (g - first)), o1 = u16(data, sub + 10 + 2 * (g - first));
					if (o1 > o0) at = imageData + o0;
				case 2:
					at = imageData + u32(data, sub + 8) * (g - first);
					big = sub + 12;
				case 4:
					var m = u32(data, sub + 8);
					for (j in 0...m)
						if (u16(data, sub + 12 + 4 * j) == g) at = imageData + u16(data, sub + 14 + 4 * j);
				case 5:
					var m = u32(data, sub + 20);
					for (j in 0...m)
						if (u16(data, sub + 24 + 2 * j) == g) at = imageData + u32(data, sub + 8) * j;
					big = sub + 12;
				case _:
			}
			if (at < 0) return null;
			// image formats 17 (small metrics), 18 (big metrics), 19 (the index's): a PNG
			var h = 0, w = 0, bx = 0, by = 0, len = 0, png = 0, adv = 0;
			switch imageFormat {
				case 17:
					h = data.get(at);
					w = data.get(at + 1);
					bx = s8(data.get(at + 2));
					by = s8(data.get(at + 3));
					adv = data.get(at + 4);
					len = u32(data, at + 5);
					png = at + 9;
				case 18:
					h = data.get(at);
					w = data.get(at + 1);
					bx = s8(data.get(at + 2));
					by = s8(data.get(at + 3));
					adv = data.get(at + 4);
					len = u32(data, at + 8);
					png = at + 12;
				case 19 if (big >= 0):
					h = data.get(big);
					w = data.get(big + 1);
					bx = s8(data.get(big + 2));
					by = s8(data.get(big + 3));
					adv = data.get(big + 4);
					len = u32(data, at);
					png = at + 4;
				case _:
					return null;
			}
			return {png: withPng ? data.sub(png, len) : null, ppem: bestPpem, left: bx, top: by, width: w, height: h, advance: adv};
		}
		return null;
	}

	// sbix: per strike, each glyph's PNG with its origin (its bottom left from the glyph's, in the strike's pixels); 'dupe': another glyph's
	function sbix(g:Int, size:Float):Null<{png:Bytes, ppem:Int, left:Int, top:Int, width:Int, height:Int}> {
		if (g < 0 || g >= numGlyphs) return null;
		var t = tables.get("sbix"), n = u32(data, t + 4), best = -1, bestPpem = 0;
		for (i in 0...n) {
			var st = t + u32(data, t + 8 + 4 * i), ppem = u16(data, st);
			if (best < 0 || (bestPpem < size ? ppem > bestPpem : ppem >= size && ppem < bestPpem)) {
				best = st;
				bestPpem = ppem;
			}
		}
		if (best < 0) return null;
		var id = g;
		for (_ in 0...4) {
			var o0 = u32(data, best + 4 + 4 * id), o1 = u32(data, best + 8 + 4 * id);
			if (o1 - o0 < 8) return null;
			var at = best + o0, type = data.getString(at + 4, 4);
			if (type == "dupe") {
				id = u16(data, at + 8);
				continue;
			}
			if (type != "png ") return null;
			var png = data.sub(at + 8, o1 - o0 - 8);
			if (png.length < 24) return null;
			var w = u32(png, 16), h = u32(png, 20);
			return {png: png, ppem: bestPpem, left: s16(data, at), top: s16(data, at + 2) + h, width: w, height: h};
		}
		return null;
	}

	// a glyph's colour layers (COLR version 0, CPAL's first palette): each a
	// glyph drawn over the ones before in its colour (ARGB; -1: the text's
	// colour); null: none
	public function colorLayers(g:Int):Null<Array<{glyph:Int, color:Int}>> {
		if (!tables.exists("COLR") || !tables.exists("CPAL")) return null;
		var c = tables.get("COLR"), n = u16(data, c + 2), base = c + u32(data, c + 4), layers = c + u32(data, c + 8);
		var lo = 0, hi = n - 1;
		while (lo <= hi) {
			var mid = (lo + hi) >> 1, r = base + 6 * mid, id = u16(data, r);
			if (id < g) lo = mid + 1 else if (id > g) hi = mid - 1 else {
				var first = u16(data, r + 2), count = u16(data, r + 4);
				var cp = tables.get("CPAL"), entries = u16(data, cp + 2), records = cp + u32(data, cp + 8), palette = u16(data, cp + 12);
				return [
					for (k in 0...count) {
						var l = layers + 4 * (first + k), index = u16(data, l + 2);
						var color = -1;
						if (index != 0xFFFF && index < entries) {
							var q = records + 4 * (palette + index);
							// (BGRA bytes)
							color = (data.get(q + 3) << 24) | (data.get(q + 2) << 16) | (data.get(q + 1) << 8) | data.get(q);
						}
						{glyph: u16(data, l), color: color};
					}
				];
			}
		}
		return null;
	}

	// --- outlines ---

	// the glyph's bounding box in font units (xMin, yMin, xMax, yMax; all 0 when empty)
	public function bounds(g:Int):Array<Int> {
		if (g < 0 || g >= numGlyphs || bitmapsOnly) return [0, 0, 0, 0];
		if (cff != null) return cff.bounds(g);
		if (coords != null) {
			// (an instance's: its varied points', control points included)
			var b = new Bounds();
			outline(g, b);
			return b.empty ? [0, 0, 0, 0] : [Math.floor(b.x0), Math.floor(b.y0), Math.ceil(b.x1), Math.ceil(b.y1)];
		}
		var start = loca(g), end = loca(g + 1);
		if (end <= start) return [0, 0, 0, 0];
		var p = glyf + start;
		return [s16(data, p + 2), s16(data, p + 4), s16(data, p + 6), s16(data, p + 8)];
	}

	// the glyph's outline in font units, y up: each contour a closed list of
	// segments (a line, a quadratic curve through a control point, or CFF's
	// cubic curves through two)
	public function outline(g:Int, out:Outline, ?transform:Array<Float>) {
		if (g < 0 || g >= numGlyphs || bitmapsOnly) return;
		if (cff != null) {
			cff.outline(g, out);
			return;
		}
		var start = loca(g), end = loca(g + 1);
		if (end <= start) return; // (an empty glyph: a space)
		var p = glyf + start;
		var contours = s16(data, p);
		var t = transform == null ? [1.0, 0, 0, 1, 0, 0] : transform;
		glyphAt = g;
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
		// (an instance: the points moved by their deltas, the origin by the first phantom point's)
		if (coords != null) {
			var dx = zeros(n + 4), dy = zeros(n + 4);
			vars.deltas(glyphAt, coords, n + 4, xs, ys, ends, dx, dy);
			for (i in 0...n) {
				xs[i] += dx[i] - dx[n];
				ys[i] += dy[i];
			}
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

	// (the glyph being read: its deltas)
	var glyphAt = 0;

	function composite(p:Int, out:Outline, t:Array<Float>) {
		var q = p + 10;
		// (an instance: the components' offsets moved by their deltas)
		var dxs:Null<haxe.ds.Vector<Float>> = null, dys:Null<haxe.ds.Vector<Float>> = null, n = 0;
		if (coords != null) {
			var r = q;
			while (true) {
				var flags = u16(data, r);
				n++;
				r += 4 + (flags & 1 != 0 ? 4 : 2) + (flags & 8 != 0 ? 2 : flags & 0x40 != 0 ? 4 : flags & 0x80 != 0 ? 8 : 0);
				if (flags & 0x20 == 0) break;
			}
			dxs = zeros(n + 4);
			dys = zeros(n + 4);
			vars.deltas(glyphAt, coords, n + 4, null, null, null, dxs, dys);
		}
		var k = 0;
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
			if (dxs != null) {
				dx += dxs[k] - dxs[n];
				dy += dys[k];
			}
			k++;
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

// (the box of an outline's points, its control points included)
private class Bounds implements Outline {
	public var x0 = Math.POSITIVE_INFINITY;
	public var y0 = Math.POSITIVE_INFINITY;
	public var x1 = Math.NEGATIVE_INFINITY;
	public var y1 = Math.NEGATIVE_INFINITY;
	public var empty(get, never):Bool;

	public function new() {}

	inline function get_empty()
		return x0 > x1;

	inline function add(x:Float, y:Float) {
		if (x < x0) x0 = x;
		if (x > x1) x1 = x;
		if (y < y0) y0 = y;
		if (y > y1) y1 = y;
	}

	public function moveTo(x:Float, y:Float)
		add(x, y);

	public function lineTo(x:Float, y:Float)
		add(x, y);

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float) {
		add(cx, cy);
		add(x, y);
	}

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float) {
		add(c1x, c1y);
		add(c2x, c2y);
		add(x, y);
	}

	public function close() {}
}
