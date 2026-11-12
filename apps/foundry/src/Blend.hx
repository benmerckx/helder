import Model;
import haxe.ds.Vector;
import helder.canvas.Canvas;
import helder.canvas.Paint;

// Faces and letters between two others: the pen, the proportions and the
// spacing in between, and each letter's shape morphed: both letters' ink
// drawn on one grid, each made a signed distance field (inside positive,
// outside negative), the fields mixed at t (0: a, 1: b) and the shape
// where the mix is inside thinned back into pen lines (Trace's skeleton).
// Letters built differently morph all the same: a serif or a slash the
// other has not fades out, an arch meets an arch.
class Blend {
	// (the mix's edge a pixel out: where the two disagree most, a stroke
	// keeps together rather than breaking at the half)
	static inline var BIAS = 4.0;

	public static function faces(a:Face, b:Face, t:Float, name:String):Face {
		var face = mixed(a, b, t, name);
		for (group in Charset.groups) {
			if (group.name == "Accented") continue;
			for (char in group.chars) {
				var g = glyph(a, b, char, t);
				if (g != null) face = Model.with(face, char, {lines: [for (l in g.lines) Freehand.snap(l, face, [])], parts: [], left: g.left, right: g.right});
			}
		}
		return face;
	}

	// a face with the pen, proportions and spacing between a's and b's, no glyphs
	public static function mixed(a:Face, b:Face, t:Float, name:String):Face {
		var pa = a.pen, pb = b.pen, ma = a.metrics, mb = b.metrics;
		return {
			name: name,
			pen: {
				width: Math.round(mix(pa.width, pb.width, t)),
				contrast: Math.round(mix(pa.contrast, pb.contrast, t) * 100) / 100,
				angle: Math.round(mix(pa.angle, pb.angle, t)),
				cap: t < 0.5 ? pa.cap : pb.cap
			},
			metrics: {
				xHeight: Math.round(mix(ma.xHeight, mb.xHeight, t)),
				capHeight: Math.round(mix(ma.capHeight, mb.capHeight, t)),
				ascender: Math.round(mix(ma.ascender, mb.ascender, t)),
				descender: Math.round(mix(ma.descender, mb.descender, t)),
				spacing: Math.round(mix(ma.spacing, mb.spacing, t))
			},
			glyphs: {}
		};
	}

	// one letter between a's and b's, in their own spaces (null: neither has it)
	public static function glyph(a:Face, b:Face, char:String, t:Float):Null<Glyph> {
		var ca = Ink.ink(a, char), cb = Ink.ink(b, char);
		if (ca.length == 0 && cb.length == 0) return null;
		var ga = Model.glyph(a, char), gb = Model.glyph(b, char);
		return {
			lines: shapes(ca, cb, t),
			parts: [],
			left: Math.round(mix(ga?.left ?? 0, gb?.left ?? 0, t)),
			right: Math.round(mix(ga?.right ?? 0, gb?.right ?? 0, t))
		};
	}

	// the pen lines of the shape between two inks (a glyph's contours, TrueType's)
	public static function shapes(ca:Array<Array<helder.text.FontEncoder.FontPoint>>, cb:Array<Array<helder.text.FontEncoder.FontPoint>>, t:Float):Array<Line> {
		if (cb.length == 0) t = 0;
		if (ca.length == 0) t = 1;
		// (both inks laid on the box between theirs: the strokes over each
		// other, else two stems apart would each fade at the half)
		var ba = box(ca), bb = box(cb);
		if (t <= 0) bb = ba;
		if (t >= 1) ba = bb;
		var x0 = mix(ba.x0, bb.x0, t), y0 = mix(ba.y0, bb.y0, t), x1 = mix(ba.x1, bb.x1, t), y1 = mix(ba.y1, bb.y1, t);
		ca = onto(ca, ba, x0, y0, x1, y1);
		cb = onto(cb, bb, x0, y0, x1, y1);
		var k = Trace.K, pad = Trace.PAD;
		var w = Math.ceil((x1 - x0) * k) + pad * 2, h = Math.ceil((y1 - y0) * k) + pad * 2;
		var fa = field(ca, w, h, x0, y1), fb = field(cb, w, h, x0, y1);
		var on = new Vector<Bool>(w * h);
		for (i in 0...w * h)
			on[i] = fa[i] * (1 - t) + fb[i] * t > -BIAS;
		var unit = (x:Float, y:Float) -> {x: (x + 0.5 - pad) / k + x0, y: y1 - (y + 0.5 - pad) / k};
		return Trace.skeleton(on, w, h, unit).lines;
	}

	static function box(cs:Array<Array<helder.text.FontEncoder.FontPoint>>):{x0:Float, y0:Float, x1:Float, y1:Float} {
		var b = {x0: Math.POSITIVE_INFINITY, y0: Math.POSITIVE_INFINITY, x1: Math.NEGATIVE_INFINITY, y1: Math.NEGATIVE_INFINITY};
		for (c in cs)
			for (p in c) {
				if (p.x < b.x0) b.x0 = p.x;
				if (p.x > b.x1) b.x1 = p.x;
				if (p.y < b.y0) b.y0 = p.y;
				if (p.y > b.y1) b.y1 = p.y;
			}
		return b;
	}

	static function onto(cs:Array<Array<helder.text.FontEncoder.FontPoint>>, b:{x0:Float, y0:Float, x1:Float, y1:Float}, x0:Float, y0:Float, x1:Float,
			y1:Float):Array<Array<helder.text.FontEncoder.FontPoint>> {
		var sx = b.x1 > b.x0 ? (x1 - x0) / (b.x1 - b.x0) : 1, sy = b.y1 > b.y0 ? (y1 - y0) / (b.y1 - b.y0) : 1;
		return [for (c in cs) [for (p in c) {x: x0 + (p.x - b.x0) * sx, y: y0 + (p.y - b.y0) * sy, on: p.on}]];
	}

	// ink drawn on the grid as a signed distance (chamfer steps: 3 a pixel)
	static function field(contours:Array<Array<helder.text.FontEncoder.FontPoint>>, w:Int, h:Int, x0:Float, y1:Float):Vector<Float> {
		var c = new Canvas(w, h);
		c.fill(Picture.path(contours, Trace.K, -x0 * Trace.K + Trace.PAD, y1 * Trace.K + Trace.PAD), Paint.solid(0xFF000000));
		var px = haxe.io.Bytes.alloc(w * h * 4);
		c.readPixels(px, 0, 0, w, h);
		var inside = new Vector<Bool>(w * h), outside = new Vector<Bool>(w * h);
		for (i in 0...w * h) {
			inside[i] = px.get(i * 4 + 3) >= 128;
			outside[i] = !inside[i];
		}
		// (the frame's edge counted as outside for the distances inside)
		for (x in 0...w) {
			outside[x] = outside[(h - 1) * w + x] = true;
			inside[x] = inside[(h - 1) * w + x] = false;
		}
		for (y in 0...h) {
			outside[y * w] = outside[y * w + w - 1] = true;
			inside[y * w] = inside[y * w + w - 1] = false;
		}
		var din = Trace.distances(inside, w, h), dout = Trace.distances(outside, w, h);
		var out = new Vector<Float>(w * h);
		for (i in 0...w * h)
			out[i] = inside[i] ? din[i] : -dout[i];
		return out;
	}

	static inline function mix(a:Float, b:Float, t:Float):Float
		return a + (b - a) * t;
}
