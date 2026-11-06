package helder.ui;

import helder.ui.Svg.SvgCanvas;
import helder.ui.Svg.SvgParse;
import helder.ui.Paint;
import helder.image.Image;

// A vector path (Canvas.path): moves, lines, quadratic and cubic curves,
// elliptical arcs (SVG's: radii, rotation, the large and sweep flags),
// closes; or SVG's path data (new Path("M4 4h16v16z")). Filled by the
// non-zero rule, or even-odd (evenOdd). Kept as numbers, curves cubic
// (quadratic ones and arcs made cubic): 0 move x y, 1 line x y, 2 cubic
// c1x c1y c2x c2y x y, 3 close. A writer (a PDF's, an SVG's) takes it as it
// is; the GPU renderer rasterizes it (render).
class Path {
	public final commands:Array<Float> = [];
	public var evenOdd = false;
	// (the pen, and where its subpath started)
	var px = 0.0;
	var py = 0.0;
	var sx = 0.0;
	var sy = 0.0;

	public function new(?d:String) {
		if (d == null) return;
		for (v in SvgParse.pathData(d))
			commands.push(v);
		// (the pen where the data left it)
		var i = 0;
		while (i < commands.length)
			switch Std.int(commands[i]) {
				case 0:
					px = sx = commands[i + 1];
					py = sy = commands[i + 2];
					i += 3;
				case 1:
					px = commands[i + 1];
					py = commands[i + 2];
					i += 3;
				case 2:
					px = commands[i + 5];
					py = commands[i + 6];
					i += 7;
				case _:
					px = sx;
					py = sy;
					i++;
			}
	}

	public function moveTo(x:Float, y:Float):Path {
		commands.push(0);
		commands.push(px = sx = x);
		commands.push(py = sy = y);
		return this;
	}

	public function lineTo(x:Float, y:Float):Path {
		commands.push(1);
		commands.push(px = x);
		commands.push(py = y);
		return this;
	}

	public function quadTo(qx:Float, qy:Float, x:Float, y:Float):Path
		return cubicTo(px + (qx - px) * 2 / 3, py + (qy - py) * 2 / 3, x + (qx - x) * 2 / 3, y + (qy - y) * 2 / 3, x, y);

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float):Path {
		for (v in [2, c1x, c1y, c2x, c2y, x, y])
			commands.push(v);
		px = x;
		py = y;
		return this;
	}

	public function arcTo(rx:Float, ry:Float, rotation:Float, large:Bool, sweep:Bool, x:Float, y:Float):Path {
		SvgParse.arc(commands, px, py, rx, ry, rotation, large, sweep, x, y);
		px = x;
		py = y;
		return this;
	}

	public function close():Path {
		commands.push(3);
		px = sx;
		py = sy;
		return this;
	}

	// a rectangle, its corners rounded by radius
	public function rect(x:Float, y:Float, w:Float, h:Float, radius = 0.0):Path {
		var r = Math.min(radius, Math.min(w, h) / 2);
		if (r <= 0) return moveTo(x, y).lineTo(x + w, y).lineTo(x + w, y + h).lineTo(x, y + h).close();
		return moveTo(x + r, y).lineTo(x + w - r, y).arcTo(r, r, 0, false, true, x + w, y + r).lineTo(x + w, y + h - r)
			.arcTo(r, r, 0, false, true, x + w - r, y + h).lineTo(x + r, y + h).arcTo(r, r, 0, false, true, x, y + h - r).lineTo(x, y + r)
			.arcTo(r, r, 0, false, true, x + r, y).close();
	}

	public function ellipse(cx:Float, cy:Float, rx:Float, ry:Float):Path {
		SvgParse.ellipse(commands, cx, cy, rx, ry);
		px = sx = cx + rx;
		py = sy = cy;
		return this;
	}

	// what its points and control points cover (an empty path: all zero)
	public function bounds():{x:Float, y:Float, width:Float, height:Float} {
		var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
		var i = 0;
		inline function at(x:Float, y:Float) {
			if (x < x0) x0 = x;
			if (x > x1) x1 = x;
			if (y < y0) y0 = y;
			if (y > y1) y1 = y;
		}
		while (i < commands.length)
			switch Std.int(commands[i]) {
				case 0 | 1:
					at(commands[i + 1], commands[i + 2]);
					i += 3;
				case 2:
					at(commands[i + 1], commands[i + 2]);
					at(commands[i + 3], commands[i + 4]);
					at(commands[i + 5], commands[i + 6]);
					i += 7;
				case _:
					i++;
			}
		return x1 < x0 ? {x: 0, y: 0, width: 0, height: 0} : {x: x0, y: y0, width: x1 - x0, height: y1 - y0};
	}

	// its pixels, w by h, filled and stroked (either may be null), its
	// units mapped to pixels by m (a, b, c, d, e, f: x' = a x + c y + e,
	// y' = b x + d y + f), drawn by helder.canvas; a gradient spans the whole image
	public function render(w:Int, h:Int, m:Array<Float>, fill:Null<Paint>, ?stroke:Stroke):Image {
		var c = new helder.canvas.Canvas(w, h), p = into(commands, new helder.canvas.Path());
		c.setTransform(m[0], m[1], m[2], m[3], m[4], m[5]);
		var paint = fill == null ? null : paintOf(fill, m, w, h);
		if (paint != null) c.fill(p, paint, evenOdd);
		paint = stroke == null || !(stroke.width > 0) ? null : paintOf(stroke.paint, m, w, h);
		if (paint != null) {
			var line = new helder.canvas.Stroke();
			SvgCanvas.strokeStyle(line, stroke.width, stroke.cap ?? Butt, stroke.join ?? Miter, stroke.miterLimit ?? 4, stroke.dashes, stroke.dashOffset ?? 0);
			c.stroke(p, line, paint);
		}
		return c.bitmap.toImage();
	}

	// (a colour, or a gradient over the w by h pixels m maps to; null: none)
	static function paintOf(p:Paint, m:Array<Float>, w:Int, h:Int):Null<helder.canvas.Paint>
		return switch (p : PaintValue) {
			case Solid(c): new helder.canvas.Paint(c);
			case Gradient(g):
				var s = g.shader(w, h), at = new helder.canvas.Matrix(m[0], m[1], m[2], m[3], m[4], m[5]);
				if (!at.invertInto(s.matrix)) null else helder.canvas.Paint.shaded(s);
		}

	// path commands (0 move, 1 line, 2 cubic, 3 close) as a canvas path, into out
	public static function into(p:Array<Float>, out:helder.canvas.Path):helder.canvas.Path {
		out.clear();
		var i = 0;
		while (i < p.length)
			switch Std.int(p[i]) {
				case 0:
					out.moveTo(p[i + 1], p[i + 2]);
					i += 3;
				case 1:
					out.lineTo(p[i + 1], p[i + 2]);
					i += 3;
				case 2:
					out.cubicTo(p[i + 1], p[i + 2], p[i + 3], p[i + 4], p[i + 5], p[i + 6]);
					i += 7;
				case _:
					out.close();
					i++;
			}
		return out;
	}
}
