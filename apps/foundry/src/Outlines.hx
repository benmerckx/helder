import Model;
import helder.text.FontFile;
import helder.text.Outline;

// A face from a font's own outlines, the whole font kept: every glyph in
// its order (under its character, else "#" and its name), its contours as
// the font has them (TrueType's quadratics raised to cubics, exactly; a
// CFF font's cubics as they are), in units of 1000 to the em (written back
// in the font's own); its metrics, each glyph's place and advance (an
// empty one's advance its own), and its layout tables (GSUB, GPOS, GDEF,
// kern), kept to be written as they are. The pen is the strokes' width (as
// Trace measures it), for lines drawn over the outlines.
class Outlines {
	// the tables kept as they are: what ligatures, alternates, figures' forms and kerning are
	static final KEPT = ["GSUB", "GPOS", "GDEF", "kern"];

	public static function face(font:FontFile, name:String):Face {
		var fs = Model.EM / font.unitsPerEm;
		function edge(cp:Int, top:Bool, fallback:Float):Float {
			var g = font.glyph(cp);
			if (g == 0) return fallback;
			var b = font.bounds(g);
			return b[0] == b[2] ? fallback : (top ? b[3] : b[1]) * fs;
		}
		// (each glyph's characters, from the character map: the Basic Multilingual Plane's)
		var codes = [for (_ in 0...font.numGlyphs) []];
		for (cp in 1...0xFFFF) {
			if (cp >= 0xD800 && cp <= 0xDFFF) continue;
			var g = font.glyph(cp);
			if (g > 0 && g < font.numGlyphs) codes[g].push(cp);
		}
		var names = postNames(font), traced = Trace.face(font, name);
		var order = [], taken = new Map<String, Bool>(), made = new Map<String, Glyph>(), sides = [];
		for (g in 0...font.numGlyphs) {
			var key = codes[g].length > 0 ? String.fromCharCode(codes[g][0]) : "#" + (names[g] ?? "g" + g);
			if (taken.exists(key)) key = key + "." + g;
			if (!Charset.unencoded(key) && taken.exists(key)) key = "#g" + g;
			taken.set(key, true);
			order.push(key);
			var c = new Collect(fs);
			font.outline(g, c);
			c.close();
			var outline = [for (k in c.contours) if (k.length > 1) Ink.tidied(Ink.smoothed(k))];
			var advance = font.advance(g) * fs, also = codes[g].length > 1 ? codes[g].slice(1) : null;
			if (outline.length == 0) {
				made.set(key, {lines: [], parts: [], outline: [], advance: advance, also: also});
				continue;
			}
			var x0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY;
			for (k in outline)
				for (p in k) {
					x0 = Math.min(x0, p.x);
					x1 = Math.max(x1, p.x);
				}
			made.set(key, {lines: [], parts: [], outline: outline, left: x0, right: advance - x1, also: also});
			if (Charset.groups[0].chars.indexOf(key) >= 0) {
				sides.push(x0);
				sides.push(advance - x1);
			}
		}
		sides.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		var spacing = sides.length == 0 ? Model.METRICS.spacing : Math.max(0, Math.round(sides[Std.int(sides.length / 2)]));
		var tables:haxe.DynamicAccess<String> = {};
		for (tag in KEPT) {
			var b = font.table(tag);
			if (b != null) tables.set(tag, haxe.crypto.Base64.encode(b));
		}
		var glyphs:haxe.DynamicAccess<Glyph> = {};
		for (key => g in made)
			glyphs.set(key, g.outline.length == 0 ? g : {
				lines: [],
				parts: [],
				outline: g.outline,
				left: Math.round(g.left - spacing),
				right: Math.round(g.right - spacing),
				also: g.also
			});
		return {
			name: name,
			pen: traced.pen,
			metrics: {
				xHeight: Math.round(edge("x".code, true, 500)),
				capHeight: Math.round(edge("H".code, true, 700)),
				ascender: Math.round(Math.max(edge("d".code, true, 740), edge("l".code, true, 740))),
				descender: Math.round(edge("p".code, false, -230)),
				spacing: spacing
			},
			glyphs: glyphs,
			source: {units: font.unitsPerEm, order: order, tables: tables}
		};
	}

	// the glyphs' names from the post table (version 2: names past the
	// Macintosh's standard 258 as strings; the standard ones left unnamed)
	static function postNames(font:FontFile):Array<Null<String>> {
		var names:Array<Null<String>> = [for (_ in 0...font.numGlyphs) null];
		var post = font.table("post");
		if (post == null || post.length < 34 || post.get(0) != 0 || post.get(1) != 2) return names;
		var n = (post.get(32) << 8) | post.get(33), at = 34 + n * 2, strings = [];
		while (at < post.length) {
			var len = post.get(at);
			if (at + 1 + len > post.length) break;
			strings.push(post.getString(at + 1, len));
			at += 1 + len;
		}
		for (g in 0...Std.int(Math.min(n, font.numGlyphs))) {
			var i = (post.get(34 + g * 2) << 8) | post.get(35 + g * 2);
			if (i >= 258 && i - 258 < strings.length) names[g] = strings[i - 258];
			if (g == 0) names[g] = ".notdef";
		}
		return names;
	}
}

// (a glyph's outline as cubic contours, in units of 1000 to the em)
private class Collect implements Outline {
	public final contours:Array<Array<OPoint>> = [];

	final fs:Float;
	var current:Array<OPoint> = [];
	var x = 0.0;
	var y = 0.0;

	public function new(fs)
		this.fs = fs;

	public function moveTo(x:Float, y:Float) {
		close();
		current.push({x: x * fs, y: y * fs});
		this.x = x * fs;
		this.y = y * fs;
	}

	public function lineTo(x:Float, y:Float) {
		current.push({x: x * fs, y: y * fs});
		this.x = x * fs;
		this.y = y * fs;
	}

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float) {
		var qx = cx * fs, qy = cy * fs, ex = x * fs, ey = y * fs;
		current.push({x: this.x + (qx - this.x) * 2 / 3, y: this.y + (qy - this.y) * 2 / 3, off: true});
		current.push({x: ex + (qx - ex) * 2 / 3, y: ey + (qy - ey) * 2 / 3, off: true});
		current.push({x: ex, y: ey});
		this.x = ex;
		this.y = ey;
	}

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float) {
		current.push({x: c1x * fs, y: c1y * fs, off: true});
		current.push({x: c2x * fs, y: c2y * fs, off: true});
		current.push({x: x * fs, y: y * fs});
		this.x = x * fs;
		this.y = y * fs;
	}

	public function close() {
		if (current.length == 0) return;
		// (the last point the first again: one)
		var a = current[0], b = current[current.length - 1];
		if (current.length > 1 && b.off != true && Math.abs(a.x - b.x) < 1e-6 && Math.abs(a.y - b.y) < 1e-6) current.pop();
		contours.push(current);
		current = [];
	}
}
