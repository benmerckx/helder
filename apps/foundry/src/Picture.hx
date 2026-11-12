import Model;
import haxe.io.Bytes;
import helder.canvas.Canvas;
import helder.canvas.Paint;
import helder.canvas.Path;
import helder.canvas.Stroke;
import helder.image.PngEncoder;

// The face drawn on the CPU (helder.canvas) as PNG: a glyph on its guides
// with its pen lines and knots, or a line of text set in it; what an agent
// looks at (Tools: glyph.snap, text.snap) to judge its own edits.
class Picture {
	static inline var PAPER = 0xFFFFFFFF;
	static inline var INK = 0xFF18181B;
	static inline var GUIDE = 0xFFD4D4D8;
	static inline var LINE = 0xFF2563EB;
	static inline var BEARING = 0xFFF0ABAB;
	static inline var HANDLE = 0xFF93B4F5;

	// one glyph, size pixels square: its ink, the guides, its spacing, its lines and knots
	public static function glyph(face:Face, char:String, size = 512):Bytes {
		var m = face.metrics, s = Ink.shape(face, char);
		var top = m.ascender + 120, bottom = m.descender - 80, scale = size / (top - bottom);
		var width = Math.max(s.advance, 400) * scale, ox = (size - width) / 2 + (width - s.advance * scale) / 2;
		var c = new Canvas(size, size);
		c.clear(PAPER);
		function y(v:Float):Float
			return (top - v) * scale;
		for (g in [m.descender, 0, m.xHeight, m.capHeight, m.ascender])
			c.fillRect(0, Math.round(y(g)), size, 1, Paint.solid(GUIDE));
		c.fillRect(Math.round(ox), 0, 1, size, Paint.solid(BEARING));
		c.fillRect(Math.round(ox + s.advance * scale), 0, 1, size, Paint.solid(BEARING));
		c.fill(path(s.contours, scale, ox, top * scale), Paint.solid(INK));
		var pen = new Path();
		for (l in Ink.lines(face, char))
			for (piece in Ink.centre(l))
				for (i in 0...piece.length) {
					var k = piece[i], px = ox + (k.x + s.dx) * scale, py = y(k.y);
					if (i == 0) pen.moveTo(px, py) else pen.lineTo(px, py);
				}
		c.stroke(pen, new Stroke(1.5), Paint.solid(LINE));
		// (the outline's points: on the curve squares, handles small)
		for (contour in Ink.outline(face, char))
			for (q in contour) {
				var dot = new Path(), r = q.off == true ? 2.0 : 3.0;
				dot.rect(ox + (q.x + s.dx) * scale - r, y(q.y) - r, r * 2, r * 2);
				c.fill(dot, Paint.solid(q.off == true ? HANDLE : LINE));
			}
		for (l in Ink.lines(face, char))
			for (k in l.knots) {
				var dot = new Path();
				dot.arc(ox + (k.x + s.dx) * scale, y(k.y), k.corner == true ? 4 : 3, 0, Math.PI * 2);
				c.fill(dot, Paint.solid(LINE));
			}
		return png(c, size, size);
	}

	// a line of text in the face, size pixels tall per em (a missing letter: a gap)
	public static function text(face:Face, text:String, size = 96):Bytes {
		var m = face.metrics, scale = size / Model.EM;
		var keys = [for (c in new haxe.iterators.StringIteratorUnicode(text)) String.fromCharCode(c)];
		var shapes = [for (ch in keys) ch == " " ? null : Ink.shape(face, ch)];
		var space = Model.EM * 0.22 + face.pen.width * 0.5, total = 0.0;
		for (s in shapes)
			total += s == null || s.contours.length == 0 ? space : s.advance;
		var pad = 24, w = Std.int(Math.min(4096, total * scale + pad * 2)), h = Std.int((m.ascender - m.descender + 200) * scale + pad * 2);
		var c = new Canvas(w, h);
		c.clear(PAPER);
		var x = pad + 0.0, base = pad + (m.ascender + 120) * scale;
		c.fillRect(0, Math.round(base), w, 1, Paint.solid(GUIDE));
		for (i in 0...shapes.length) {
			var s = shapes[i];
			if (i > 0) x += Model.kern(face, keys[i - 1], keys[i]) * scale;
			if (s == null || s.contours.length == 0) {
				x += space * scale;
				continue;
			}
			c.fill(path(s.contours, scale, x, base), Paint.solid(INK));
			x += s.advance * scale;
		}
		return png(c, w, h);
	}

	// contours in font units as a path in pixels (y down from base)
	public static function path(contours:Array<Array<helder.text.FontEncoder.FontPoint>>, scale:Float, ox:Float, base:Float):Path {
		var p = new Path();
		for (c in contours) {
			if (c.length == 0) continue;
			var n = c.length, start = 0;
			while (start < n && !c[start].on)
				start++;
			if (start == n) continue;
			inline function px(i:Int)
				return ox + c[i % n].x * scale;
			inline function py(i:Int)
				return base - c[i % n].y * scale;
			p.moveTo(px(start), py(start));
			var i = 1;
			while (i <= n) {
				var k = (start + i) % n;
				if (c[k].on) {
					p.lineTo(px(k), py(k));
					i++;
				} else {
					var next = (k + 1) % n;
					if (c[next].on) {
						p.quadTo(px(k), py(k), px(next), py(next));
						i += 2;
					} else {
						p.quadTo(px(k), py(k), (px(k) + px(next)) / 2, (py(k) + py(next)) / 2);
						i++;
					}
				}
			}
			p.close();
		}
		return p;
	}

	static function png(c:Canvas, w:Int, h:Int):Bytes {
		var px = Bytes.alloc(w * h * 4);
		c.readPixels(px, 0, 0, w, h);
		return PngEncoder.encode(px, w, h, true);
	}
}
