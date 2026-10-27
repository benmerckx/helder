package helder.ui;

import helder.ui.Svg;
import helder.ui.Paint;

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
	// y' = b x + d y + f); a gradient spans the whole image
	public function render(w:Int, h:Int, m:Array<Float>, fill:Null<Paint>, ?stroke:Stroke):Image {
		var out:Null<Image> = null;
		for (part in 0...2) {
			var paint:Null<Paint> = part == 0 ? fill : stroke == null ? null : stroke.paint;
			if (paint == null || part == 1 && stroke.width <= 0) continue;
			var style = new SvgStyle();
			style.evenOdd = evenOdd;
			var solid:Color = switch (paint : PaintValue) {
				case Solid(c): c;
				case Gradient(_): Color.WHITE;
			}
			if (part == 0) style.fill = Rgba(solid) else {
				style.fill = None;
				style.stroke = Rgba(solid);
				style.strokeWidth = stroke.width;
				style.cap = stroke.cap ?? Butt;
				style.join = stroke.join ?? Miter;
				style.miterLimit = stroke.miterLimit ?? 4;
				style.dashes = stroke.dashes;
				style.dashOffset = stroke.dashOffset ?? 0;
			}
			var g = new SvgGroup(Matrix.identity(), 1);
			g.children.push(new SvgShape(commands, Matrix.identity(), style, 1));
			var canvas = new SvgCanvas(w, h, Color.BLACK);
			canvas.group(g, new Matrix(m[0], m[1], m[2], m[3], m[4], m[5]));
			var layer = canvas.image();
			switch (paint : PaintValue) {
				case Gradient(gr):
					// (the coverage in the gradient's colours)
					var gi = gr.render(w, h), a = layer.pixels, b = gi.pixels;
					for (k in 0...w * h) {
						var o = k * 4;
						a.set(o, b.get(o));
						a.set(o + 1, b.get(o + 1));
						a.set(o + 2, b.get(o + 2));
						a.set(o + 3, Std.int((a.get(o + 3) * b.get(o + 3) + 127) / 255));
					}
				case Solid(_):
			}
			out = out == null ? layer : over(out, layer);
		}
		return out ?? new Image(w, h);
	}

	// (b over a, straight alpha)
	static function over(a:Image, b:Image):Image {
		var p = a.pixels, q = b.pixels;
		for (k in 0...a.width * a.height) {
			var o = k * 4, sa = q.get(o + 3) / 255;
			if (sa <= 0) continue;
			var da = p.get(o + 3) / 255, oa = sa + da * (1 - sa);
			for (c in 0...3)
				p.set(o + c, Std.int(Math.round((q.get(o + c) * sa + p.get(o + c) * da * (1 - sa)) / oa)));
			p.set(o + 3, Std.int(Math.round(oa * 255)));
		}
		return a;
	}
}
