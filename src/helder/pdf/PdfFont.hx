package helder.pdf;

import haxe.io.Bytes;
import helder.canvas.Matrix;
import helder.canvas.Path;
import helder.pdf.PdfValue;
import helder.pdf.Document;
import helder.pdf.Colors;

import helder.text.FontFile;

// A page's font: its codes (one byte, or a CMap's for a composite font),
// each code's glyph as an outline and its advance (the font's /Widths, /W
// in thousandths of the text space), from its embedded program
// (TrueType and OpenType through helder.text's FontFile, bare CFF through
// helder.text's Cff with its charset read here, Type 1 through Type1), a
// Type 3 font's glyph procedures (the interpreter draws them), or, for a
// font not embedded, a system face by its name (Times: serif, Courier:
// monospace, others sans-serif), at the widths the file gives.
class PdfFont {
	public var type3(default, null) = false;
	public var composite(default, null) = false;
	public var vertical(default, null) = false;
	// glyph space to text space (a thousand an em; Type 3's FontMatrix)
	public var matrix(default, null) = new Matrix(0.001, 0, 0, 0.001, 0, 0);
	public var resources(default, null):Null<PdfDict> = null;
	public var charProcs(default, null):Null<PdfDict> = null;

	final doc:Document;
	final widths = new Map<Int, Float>();
	var defaultWidth = 0.0;
	var missingWidth = 0.0;
	// a simple font's code -> glyph name
	final names:Array<Null<String>> = [for (_ in 0...256) null];
	var symbolic = false;
	var face:Null<FontFile> = null;
	var cff:Null<helder.text.Cff> = null;
	var cffCharset:Null<Map<String, Int>> = null;
	var cffCids:Null<Map<Int, Int>> = null;
	var type1:Null<Type1> = null;
	var cidToGid:Null<Bytes> = null;
	var cmap:Null<CMap> = null;
	var unitsPerEm = 1000.0;

	public function new(doc:Document, d:PdfDict) {
		this.doc = doc;
		var subtype = Values.name(d.get("Subtype"), "Type1");
		if (subtype == "Type0") {
			composite = true;
			var enc = doc.resolve(d.get("Encoding"));
			cmap = switch enc {
				case PName(n):
					vertical = StringTools.endsWith(n, "-V");
					CMap.identity();
				case PStream(_, _): CMap.parse(doc.stream(enc));
				case _: CMap.identity();
			}
			var desc = Values.arr(doc.resolve(d.get("DescendantFonts")));
			var cid = desc != null && desc.length > 0 ? Values.dict(doc.resolve(desc[0])) : null;
			if (cid == null) throw PdfError.corrupt("a Type0 font without its CIDFont");
			defaultWidth = Values.num(cid.get("DW"), 1000);
			var w = Values.arr(doc.resolve(cid.get("W")));
			if (w != null) {
				var i = 0;
				while (i < w.length) {
					var first = Values.int(doc.resolve(w[i]));
					var next = doc.resolve(i + 1 < w.length ? w[i + 1] : PNull);
					switch next {
						case PArray(list):
							for (k in 0...list.length)
								widths.set(first + k, Values.num(doc.resolve(list[k])));
							i += 2;
						case _:
							var last = Values.int(next), width = Values.num(doc.resolve(i + 2 < w.length ? w[i + 2] : PNull));
							if (last - first > 65536) last = first + 65536;
							for (k in first...last + 1)
								widths.set(k, width);
							i += 3;
					}
				}
			}
			var map = doc.resolve(cid.get("CIDToGIDMap"));
			switch map {
				case PStream(_, _): cidToGid = doc.stream(map);
				case _:
			}
			loadProgram(Values.dict(doc.resolve(cid.get("FontDescriptor"))), Values.name(cid.get("BaseFont"), ""));
			return;
		}
		if (subtype == "Type3") {
			type3 = true;
			var fm = Values.nums(doc.resolve(d.get("FontMatrix")));
			if (fm != null && fm.length == 6) matrix = new Matrix(fm[0], fm[1], fm[2], fm[3], fm[4], fm[5]);
			charProcs = Values.dict(doc.resolve(d.get("CharProcs")));
			resources = Values.dict(doc.resolve(d.get("Resources")));
		}
		var first = Values.int(doc.resolve(d.get("FirstChar")));
		var ws = Values.arr(doc.resolve(d.get("Widths")));
		if (ws != null)
			for (k in 0...ws.length)
				widths.set(first + k, Values.num(doc.resolve(ws[k])));
		var fd = Values.dict(doc.resolve(d.get("FontDescriptor")));
		if (fd != null) {
			missingWidth = Values.num(fd.get("MissingWidth"));
			symbolic = (Values.int(fd.get("Flags")) & 4) != 0;
		}
		var base = Values.name(d.get("BaseFont"), "");
		if (!type3) loadProgram(fd, base);
		// the encoding: the base's (or the font's own), then the differences
		var enc = doc.resolve(d.get("Encoding"));
		var baseNames:Null<Array<Null<String>>> = null, diffs:Null<Array<PdfValue>> = null;
		switch enc {
			case PName(n):
				baseNames = Encodings.named(n);
			case PDict(e):
				baseNames = Encodings.named(Values.name(e.get("BaseEncoding")));
				diffs = Values.arr(doc.resolve(e.get("Differences")));
			case _:
		}
		if (baseNames == null) {
			if (type1 != null) {
				for (c => n in type1.encoding)
					if (c >= 0 && c < 256) names[c] = n;
			} else if (!symbolic || face == null) baseNames = Encodings.standardEncoding();
		}
		if (baseNames != null)
			for (c in 0...256)
				names[c] = baseNames[c];
		if (diffs != null) {
			var code = 0;
			for (x in diffs)
				switch x {
					case PNum(n): code = Std.int(n);
					case PName(n):
						if (code >= 0 && code < 256) names[code] = n;
						code++;
					case _:
				}
		}
	}

	function loadProgram(fd:Null<PdfDict>, base:String) {
		if (fd != null) {
			var f1 = doc.resolve(fd.get("FontFile")), f2 = doc.resolve(fd.get("FontFile2")), f3 = doc.resolve(fd.get("FontFile3"));
			try {
				if (f2 != PNull) {
					face = FontFile.parse(doc.stream(f2));
					unitsPerEm = face.unitsPerEm;
					return;
				}
				if (f3 != PNull) {
					var sub = Values.name(Values.dict(f3).get("Subtype"), "");
					var bytes = doc.stream(f3);
					if (sub == "OpenType" || (bytes.length > 4 && bytes.getString(0, 4) == "OTTO")) {
						face = FontFile.parse(bytes);
						unitsPerEm = face.unitsPerEm;
						return;
					}
					cff = new helder.text.Cff(bytes, 0, 1000);
					var cs = CffCharset.read(bytes);
					cffCharset = cs.names;
					cffCids = cs.cids;
					return;
				}
				if (f1 != PNull) {
					type1 = new Type1(doc.stream(f1), Values.int(Values.dict(f1).get("Length1")));
					return;
				}
			} catch (e:PdfError) {
				if (e.kind == TooLarge) throw e;
			} catch (_:Dynamic) {}
		}
		// (not embedded, or not read: a system face by the name's kind)
		var n = base.toLowerCase();
		var fonts = helder.text.SystemFonts.get();
		var family = n.indexOf("times") >= 0 || n.indexOf("serif") >= 0 && n.indexOf("sans") < 0 || n.indexOf("georgia") >= 0 ? "serif" : n.indexOf("courier") >= 0
			|| n.indexOf("mono") >= 0 ? "monospace" : "sans-serif";
		var bold = n.indexOf("bold") >= 0 || n.indexOf("black") >= 0 || n.indexOf("heavy") >= 0;
		var italic = n.indexOf("italic") >= 0 || n.indexOf("oblique") >= 0;
		// (Liberation's faces first: Helvetica's, Times' and Courier's metrics)
		var metric = family == "serif" ? "Liberation Serif" : family == "monospace" ? "Liberation Mono" : "Liberation Sans";
		face = fonts.match(metric, bold ? 700 : 400, italic);
		if (face == null || face.family.indexOf("Liberation") < 0) face = fonts.match(family, bold ? 700 : 400, italic);
		if (face != null) unitsPerEm = face.unitsPerEm;
		substitute = true;
	}

	var substitute = false;
	var codeCmap:Null<Map<Int, Int>> = null;

	// the next code in s at i: its value and its byte length into out
	public function code(s:Bytes, i:Int, out:Array<Int>) {
		if (!composite) {
			out[0] = s.get(i);
			out[1] = 1;
			return;
		}
		cmap.next(s, i, out);
	}

	// a code's advance in thousandths of the text space's unit (horizontal)
	public function width(code:Int):Float {
		if (composite) {
			var cid = cmap.cid(code);
			var w = widths.get(cid);
			return w ?? defaultWidth;
		}
		var w = widths.get(code);
		if (w != null) return w;
		if (face != null) {
			var g = glyphOf(code);
			if (g > 0) return face.advance(g) * 1000 / unitsPerEm;
		}
		return missingWidth;
	}

	public function glyphName(code:Int):Null<String>
		return code >= 0 && code < 256 ? names[code] : null;

	// a TrueType or OpenType face's glyph for a code (0: none)
	function glyphOf(code:Int):Int {
		if (face == null) return 0;
		if (composite) {
			var cid = cmap.cid(code);
			if (substitute) return face.glyph(cmap.unicode(code, cid));
			if (cidToGid != null) return cid * 2 + 1 < cidToGid.length ? (cidToGid.get(cid * 2) << 8) | cidToGid.get(cid * 2 + 1) : 0;
			return cid;
		}
		var name = names[code];
		if (!symbolic || substitute) {
			var u = name != null ? Encodings.unicode(name) : -1;
			if (u < 0 && substitute) u = code;
			if (u >= 0) {
				var g = face.glyph(u);
				if (g > 0) return g;
			}
		}
		// (a symbolic font's own codes: its (3,0) and (1,0) subtables, read here; then the code itself)
		if (!substitute) {
			if (codeCmap == null) codeCmap = SymbolCmap.read(face.data, face.faceIndex);
			var g = codeCmap.get(0xF000 + code) ?? codeCmap.get(code);
			if (g != null && g > 0) return g;
		}
		var g = face.glyph(0xF000 + code);
		if (g > 0) return g;
		g = face.glyph(code);
		if (g > 0) return g;
		return substitute ? 0 : code;
	}

	// the code's glyph outline into path through m (glyph units: a thousand an em in; m from text space by matrix)
	public function outline(code:Int, path:Path, m:Matrix) {
		var gm = m.clone().multiply(matrix);
		if (type1 != null) {
			var name = names[code] ?? ".notdef";
			var fm = type1.fontMatrix;
			// (its own FontMatrix to text space, not Type 1's default thousandth)
			type1.outline(name, path, m.clone().multiply(new Matrix(fm[0], fm[1], fm[2], fm[3], fm[4], fm[5])));
			return;
		}
		if (cff != null) {
			var gid = 0;
			if (composite) {
				var cid = cmap.cid(code);
				gid = cffCids != null && cffCids.exists(cid) ? cffCids.get(cid) : cid;
			} else {
				var name = names[code];
				gid = name != null && cffCharset != null && cffCharset.exists(name) ? cffCharset.get(name) : 0;
			}
			cff.outline(gid, new PathSink(path, gm));
			return;
		}
		if (face == null) return;
		var g = glyphOf(code);
		if (g <= 0) return;
		// (font units to glyph space's thousandths; a substitute squeezed or widened to the file's width)
		var k = 1000 / unitsPerEm, kx = k;
		if (substitute && widths.exists(code)) {
			var own = face.advance(g) * k;
			if (own > 0) kx = k * Math.max(0.5, Math.min(2, widths.get(code) / own));
		}
		face.outline(g, new PathSink(path, gm.clone().scale(kx, k)));
	}
}

// Outline calls into a Path through a matrix
class PathSink implements helder.text.Outline {
	final p:Path;
	final m:Matrix;

	public function new(p, m) {
		this.p = p;
		this.m = m;
	}

	public function moveTo(x:Float, y:Float)
		p.moveTo(m.mapX(x, y), m.mapY(x, y));

	public function lineTo(x:Float, y:Float)
		p.lineTo(m.mapX(x, y), m.mapY(x, y));

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float)
		p.quadTo(m.mapX(cx, cy), m.mapY(cx, cy), m.mapX(x, y), m.mapY(x, y));

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float)
		p.cubicTo(m.mapX(c1x, c1y), m.mapY(c1x, c1y), m.mapX(c2x, c2y), m.mapY(c2x, c2y), m.mapX(x, y), m.mapY(x, y));

	public function close()
		p.close();
}

// A composite font's CMap: codespace ranges (codes of 1 to 4 bytes), cid
// ranges and single cids; Identity-H and -V: two bytes, the code the cid.
// The ToUnicode CMaps' bfrange and bfchar are read the same way (a
// substitute face's characters)
class CMap {
	final spaces:Array<Array<Int>> = [];
	final ranges:Array<Array<Int>> = [];
	final singles = new Map<Int, Int>();
	var isIdentity = false;

	function new() {}

	public static function identity():CMap {
		var c = new CMap();
		c.isIdentity = true;
		return c;
	}

	public static function parse(b:Bytes):CMap {
		var c = new CMap();
		var p = new Parser(b);
		var stack:Array<PdfValue> = [];
		var mode = "";
		var ops = 0;
		while (p.pos < p.end && ops++ < 2000000) {
			var v = p.next();
			if (v != null) {
				stack.push(v);
				continue;
			}
			var k = p.keyword;
			if (k == "" && p.pos >= p.end) break;
			switch k {
				case "begincodespacerange" | "begincidrange" | "begincidchar":
					mode = k;
					stack.resize(0);
				case "endcodespacerange":
					var i = 0;
					while (i + 1 < stack.length) {
						var lo = Values.str(stack[i]), hi = Values.str(stack[i + 1]);
						if (lo != null && hi != null) c.spaces.push([lo.length, num(lo), num(hi)]);
						i += 2;
					}
					stack.resize(0);
				case "endcidrange":
					var i = 0;
					while (i + 2 < stack.length) {
						var lo = Values.str(stack[i]), hi = Values.str(stack[i + 1]);
						if (lo != null && hi != null) c.ranges.push([num(lo), num(hi), Values.int(stack[i + 2])]);
						i += 3;
					}
					stack.resize(0);
				case "endcidchar":
					var i = 0;
					while (i + 1 < stack.length) {
						var lo = Values.str(stack[i]);
						if (lo != null) c.singles.set(num(lo), Values.int(stack[i + 1]));
						i += 2;
					}
					stack.resize(0);
				case "usecmap":
					// (a predefined CMap by name: two-byte codes as Identity's)
					c.isIdentity = c.ranges.length == 0;
					stack.resize(0);
				case _:
					stack.resize(0);
			}
		}
		if (c.spaces.length == 0) c.spaces.push([2, 0, 0xFFFF]);
		return c;
	}

	static function num(b:Bytes):Int {
		var v = 0;
		for (i in 0...Std.int(Math.min(4, b.length)))
			v = (v << 8) | b.get(i);
		return v;
	}

	public function next(s:Bytes, i:Int, out:Array<Int>) {
		if (isIdentity || spaces.length == 0) {
			out[0] = i + 1 < s.length ? (s.get(i) << 8) | s.get(i + 1) : s.get(i);
			out[1] = i + 1 < s.length ? 2 : 1;
			return;
		}
		var v = 0;
		for (n in 1...5) {
			if (i + n > s.length) break;
			v = (v << 8) | s.get(i + n - 1);
			for (sp in spaces)
				if (sp[0] == n && v >= sp[1] && v <= sp[2]) {
					out[0] = v;
					out[1] = n;
					return;
				}
		}
		out[0] = s.get(i);
		out[1] = 1;
	}

	public function cid(code:Int):Int {
		if (isIdentity) return code;
		var s = singles.get(code);
		if (s != null) return s;
		for (r in ranges)
			if (code >= r[0] && code <= r[1]) return r[2] + code - r[0];
		return 0;
	}

	public function unicode(code:Int, cid:Int):Int
		return cid;
}

// A bare CFF's charset: glyph names (or a CID-keyed font's cids) to glyph ids
class CffCharset {
	static final STD = ".notdef space exclam quotedbl numbersign dollar percent ampersand quoteright parenleft parenright asterisk plus comma hyphen period slash zero one two three four five six seven eight nine colon semicolon less equal greater question at A B C D E F G H I J K L M N O P Q R S T U V W X Y Z bracketleft backslash bracketright asciicircum underscore quoteleft a b c d e f g h i j k l m n o p q r s t u v w x y z braceleft bar braceright asciitilde exclamdown cent sterling fraction yen florin section currency quotesingle quotedblleft guillemotleft guilsinglleft guilsinglright fi fl endash dagger daggerdbl periodcentered paragraph bullet quotesinglbase quotedblbase quotedblright guillemotright ellipsis perthousand questiondown grave acute circumflex tilde macron breve dotaccent dieresis ring cedilla hungarumlaut ogonek caron emdash AE ordfeminine Lslash Oslash OE ordmasculine ae dotlessi lslash oslash oe germandbls onesuperior logicalnot mu trademark Eth onehalf plusminus Thorn onequarter divide brokenbar degree thorn threequarters twosuperior registered minus eth multiply threesuperior copyright Aacute Acircumflex Adieresis Agrave Aring Atilde Ccedilla Eacute Ecircumflex Edieresis Egrave Iacute Icircumflex Idieresis Igrave Ntilde Oacute Ocircumflex Odieresis Ograve Otilde Scaron Uacute Ucircumflex Udieresis Ugrave Yacute Ydieresis Zcaron aacute acircumflex adieresis agrave aring atilde ccedilla eacute ecircumflex edieresis egrave iacute icircumflex idieresis igrave ntilde oacute ocircumflex odieresis ograve otilde scaron uacute ucircumflex udieresis ugrave yacute ydieresis zcaron".split(" ");

	public static function read(b:Bytes):{names:Map<String, Int>, cids:Null<Map<Int, Int>>} {
		var hdr = b.get(2);
		var p = hdr;
		inline function u16(o:Int):Int
			return (b.get(o) << 8) | b.get(o + 1);
		// (an INDEX: its count, offsets, data; the position after it)
		function index(at:Int):{items:Array<Bytes>, end:Int} {
			var count = u16(at);
			if (count == 0) return {items: [], end: at + 2};
			var os = b.get(at + 2);
			inline function off(k:Int):Int {
				var v = 0;
				for (j in 0...os)
					v = (v << 8) | b.get(at + 3 + k * os + j);
				return v;
			}
			var base = at + 3 + (count + 1) * os - 1, items = [];
			for (k in 0...count)
				items.push(b.sub(base + off(k), off(k + 1) - off(k)));
			return {items: items, end: base + off(count)};
		}
		var names = index(p);
		var tops = index(names.end);
		var strings = index(tops.end);
		var top = tops.items.length > 0 ? dict(tops.items[0]) : new Map<Int, Array<Float>>();
		var charStringsAt = top.exists(17) ? Std.int(top.get(17)[0]) : -1;
		var nGlyphs = charStringsAt >= 0 ? u16(charStringsAt) : 0;
		var charset = top.exists(15) ? Std.int(top.get(15)[0]) : 0;
		var cid = top.exists(1230);
		inline function sid(s:Int):String
			return s < STD.length ? STD[s] : s - STD.length < strings.items.length ? strings.items[s - STD.length].toString() : "";
		var map = new Map<String, Int>(), cids = cid ? new Map<Int, Int>() : null;
		map.set(".notdef", 0);
		if (charset > 2 && charset < b.length) {
			var fmt = b.get(charset), q = charset + 1, g = 1;
			while (g < nGlyphs && q < b.length) {
				if (fmt == 0) {
					var s = u16(q);
					q += 2;
					if (cid) cids.set(s, g) else map.set(sid(s), g);
					g++;
				} else {
					var first = u16(q), n = fmt == 1 ? b.get(q + 2) : u16(q + 2);
					q += fmt == 1 ? 3 : 4;
					for (k in 0...n + 1) {
						if (g >= nGlyphs) break;
						if (cid) cids.set(first + k, g) else map.set(sid(first + k), g);
						g++;
					}
				}
			}
		} else if (!cid)
			for (g in 1...Std.int(Math.min(nGlyphs, STD.length)))
				map.set(STD[g], g);
		return {names: map, cids: cids};
	}

	// a DICT's operators (12 x: 1200 + x) and their operands
	static function dict(d:Bytes):Map<Int, Array<Float>> {
		var out = new Map<Int, Array<Float>>(), ops:Array<Float> = [], i = 0;
		while (i < d.length) {
			var v = d.get(i);
			if (v <= 21) {
				var op = v;
				i++;
				if (v == 12 && i < d.length) op = 1200 + d.get(i++);
				out.set(op, ops);
				ops = [];
			} else if (v == 28) {
				ops.push(((d.get(i + 1) << 8) | d.get(i + 2)) << 16 >> 16);
				i += 3;
			} else if (v == 29) {
				ops.push((d.get(i + 1) << 24) | (d.get(i + 2) << 16) | (d.get(i + 3) << 8) | d.get(i + 4));
				i += 5;
			} else if (v == 30) {
				i++;
				while (i < d.length) {
					var c = d.get(i++);
					if ((c & 15) == 15 || (c >> 4) == 15) break;
				}
				ops.push(0);
			} else if (v >= 32 && v <= 246) {
				ops.push(v - 139);
				i++;
			} else if (v >= 247 && v <= 250) {
				ops.push((v - 247) * 256 + d.get(i + 1) + 108);
				i += 2;
			} else if (v >= 251 && v <= 254) {
				ops.push(-(v - 251) * 256 - d.get(i + 1) - 108);
				i += 2;
			} else
				i++;
		}
		return out;
	}
}

// A TrueType font's (3,0) and (1,0) cmap subtables (formats 0, 4, 6): a symbolic font's codes to glyphs
class SymbolCmap {
	public static function read(b:Bytes, face:Int):Map<Int, Int> {
		var out = new Map<Int, Int>();
		try {
			inline function u16(o:Int):Int
				return (b.get(o) << 8) | b.get(o + 1);
			inline function u32(o:Int):Int
				return (b.get(o) << 24) | (b.get(o + 1) << 16) | (b.get(o + 2) << 8) | b.get(o + 3);
			var base = 0;
			if (b.getString(0, 4) == "ttcf") base = u32(12 + face * 4);
			var n = u16(base + 4), cmap = -1;
			for (i in 0...n) {
				var r = base + 12 + i * 16;
				if (b.getString(r, 4) == "cmap") cmap = u32(r + 8);
			}
			if (cmap < 0) return out;
			var count = u16(cmap + 2);
			for (i in 0...count) {
				var r = cmap + 4 + i * 8, platform = u16(r), enc = u16(r + 2), at = cmap + u32(r + 4);
				if (!((platform == 3 && enc == 0) || platform == 1)) continue;
				var fmt = u16(at);
				if (fmt == 0) for (c in 0...256) {
					var g = b.get(at + 6 + c);
					if (g > 0 && !out.exists(c)) out.set(c, g);
				} else if (fmt == 6) {
					var first = u16(at + 6), cnt = u16(at + 8);
					for (k in 0...cnt) {
						var g = u16(at + 10 + k * 2);
						if (g > 0 && !out.exists(first + k)) out.set(first + k, g);
					}
				} else if (fmt == 4) {
					var segs = u16(at + 6) >> 1;
					var ends = at + 14, starts = ends + segs * 2 + 2, deltas = starts + segs * 2, offs = deltas + segs * 2;
					for (sg in 0...segs) {
						var e = u16(ends + sg * 2), st = u16(starts + sg * 2), d = u16(deltas + sg * 2), ro = u16(offs + sg * 2);
						if (e - st > 4096) continue;
						for (c in st...e + 1) {
							if (c == 0xFFFF) continue;
							var g = ro == 0 ? (c + d) & 0xFFFF : {
								var gi = u16(offs + sg * 2 + ro + (c - st) * 2);
								gi == 0 ? 0 : (gi + d) & 0xFFFF;
							}
							if (g > 0 && !out.exists(c)) out.set(c, g);
						}
					}
				}
			}
		} catch (_:Dynamic) {}
		return out;
	}
}
