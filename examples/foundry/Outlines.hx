import Model;
import helder.text.FontFile;
import helder.text.Outline;

// A face from a font's own outlines, kept exact: each letter's contours as
// the font has them (TrueType's quadratics raised to cubics, exactly; a
// CFF font's cubics as they are), in units of 1000 to the em; its
// metrics, and each letter's place and advance, the font's. Accented
// letters are left to be made of their letter and accent, as Foundry
// makes them. The pen is the strokes' width (as Trace measures it), for
// lines drawn over the outlines.
class Outlines {
	public static function face(font:FontFile, name:String):Face {
		var fs = Model.EM / font.unitsPerEm;
		function edge(cp:Int, top:Bool, fallback:Float):Float {
			var g = font.glyph(cp);
			if (g == 0) return fallback;
			var b = font.bounds(g);
			return b[0] == b[2] ? fallback : (top ? b[3] : b[1]) * fs;
		}
		var face = Model.empty(name);
		var traced = Trace.face(font, name);
		var made = new Map<String, {outline:Array<Array<OPoint>>, x0:Float, x1:Float, advance:Float}>(), sides = [];
		for (group in Charset.groups) {
			if (group.name == "Accented") continue;
			for (char in group.chars) {
				var g = font.glyph(Charset.code(char));
				if (g == 0) continue;
				var c = new Collect(fs);
				font.outline(g, c);
				c.close();
				var outline = [for (k in c.contours) if (k.length > 1) Ink.tidied(Ink.smoothed(k))];
				if (outline.length == 0) continue;
				var x0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY;
				for (k in outline)
					for (p in k) {
						x0 = Math.min(x0, p.x);
						x1 = Math.max(x1, p.x);
					}
				var advance = font.advance(g) * fs;
				made.set(char, {outline: outline, x0: x0, x1: x1, advance: advance});
				if (group.name == "Lowercase") {
					sides.push(x0);
					sides.push(advance - x1);
				}
			}
		}
		sides.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		var spacing = sides.length == 0 ? Model.METRICS.spacing : Math.max(0, Math.round(sides[Std.int(sides.length / 2)]));
		face = {
			name: name,
			pen: traced.pen,
			metrics: {
				xHeight: Math.round(edge("x".code, true, 500)),
				capHeight: Math.round(edge("H".code, true, 700)),
				ascender: Math.round(Math.max(edge("d".code, true, 740), edge("l".code, true, 740))),
				descender: Math.round(edge("p".code, false, -230)),
				spacing: spacing
			},
			glyphs: {}
		};
		for (char => m in made)
			face = Model.with(face, char, {
				lines: [],
				parts: [],
				outline: m.outline,
				left: Math.round(m.x0 - spacing),
				right: Math.round(m.advance - m.x1 - spacing)
			});
		return face;
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
