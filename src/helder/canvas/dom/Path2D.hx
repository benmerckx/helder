package helder.canvas.dom;

import helder.canvas.Path;

// The browser's Path2D: a path of its own, filled, stroked or clipped by
// a context with its transform at that time. Made empty, from another
// Path2D, or from SVG path data ("M 10 10 h 80 v 80 Z").
class Path2D {
	@:noCompletion public final path:Path = new Path();

	public function new(?init:Dynamic) {
		if (init == null) return;
		if (Std.isOfType(init, Path2D)) path.addPath((init : Path2D).path) else if (Std.isOfType(init, String)) SvgPath.parse(init, path);
	}

	// another path's subpaths, through a transform when given
	public function addPath(other:Path2D, ?transform:DOMMatrix) {
		if (transform == null) path.addPath(other.path) else path.addPath(other.path, transform.into(new helder.canvas.Matrix()));
	}

	// skia-canvas's extras: boolean operations (each a new path), simplify,
	// and effects (rounded corners, trimmed by length, jittered), a move and a transform
	public function union(other:Path2D):Path2D
		return of(helder.canvas.PathOps.union(path, other.path));

	public function intersect(other:Path2D):Path2D
		return of(helder.canvas.PathOps.intersect(path, other.path));

	public function difference(other:Path2D):Path2D
		return of(helder.canvas.PathOps.difference(path, other.path));

	public function xor(other:Path2D):Path2D
		return of(helder.canvas.PathOps.xor(path, other.path));

	public function complement(other:Path2D):Path2D
		return of(helder.canvas.PathOps.difference(other.path, path));

	public function simplify(rule = "nonzero"):Path2D
		return of(helder.canvas.PathOps.simplify(path, rule == "evenodd"));

	public function round(radius:Float):Path2D
		return of(helder.canvas.PathEffects.round(path, radius));

	public function trim(start:Float, end:Float, inverted = false):Path2D
		return of(helder.canvas.PathEffects.trim(path, start, end, inverted));

	public function jitter(segmentLength:Float, amount:Float, seed = 0):Path2D
		return of(helder.canvas.PathEffects.jitter(path, segmentLength, amount, seed));

	public function dash(segments:Array<Float>, offset = 0.0):Path2D
		return of(helder.canvas.PathEffects.dash(path, segments, offset));

	public function offset(dx:Float, dy:Float):Path2D {
		var p = new Path2D();
		p.path.addPath(path, new helder.canvas.Matrix(1, 0, 0, 1, dx, dy));
		return p;
	}

	public function transform(m:DOMMatrix):Path2D {
		var p = new Path2D();
		p.path.addPath(path, m.into(new helder.canvas.Matrix()));
		return p;
	}

	@:noCompletion public static function of(p:Path):Path2D {
		var r = new Path2D();
		r.path.addPath(p);
		return r;
	}

	public function closePath()
		path.close();

	public function moveTo(x:Float, y:Float)
		path.moveTo(x, y);

	public function lineTo(x:Float, y:Float)
		path.lineTo(x, y);

	public function quadraticCurveTo(cpx:Float, cpy:Float, x:Float, y:Float)
		path.quadTo(cpx, cpy, x, y);

	public function bezierCurveTo(cp1x:Float, cp1y:Float, cp2x:Float, cp2y:Float, x:Float, y:Float)
		path.cubicTo(cp1x, cp1y, cp2x, cp2y, x, y);

	public function arc(x:Float, y:Float, radius:Float, startAngle:Float, endAngle:Float, anticlockwise = false) {
		if (!Math.isFinite(x + y + radius + startAngle + endAngle)) return;
		if (radius < 0) throw new DOMException("IndexSizeError", "The radius provided (" + radius + ") is negative.");
		path.arc(x, y, radius, startAngle, endAngle, anticlockwise);
	}

	public function arcTo(x1:Float, y1:Float, x2:Float, y2:Float, radius:Float) {
		if (!Math.isFinite(x1 + y1 + x2 + y2 + radius)) return;
		if (radius < 0) throw new DOMException("IndexSizeError", "The radius provided (" + radius + ") is negative.");
		path.arcTo(x1, y1, x2, y2, radius);
	}

	public function ellipse(x:Float, y:Float, radiusX:Float, radiusY:Float, rotation:Float, startAngle:Float, endAngle:Float, anticlockwise = false) {
		if (!Math.isFinite(x + y + radiusX + radiusY + rotation + startAngle + endAngle)) return;
		if (radiusX < 0 || radiusY < 0) throw new DOMException("IndexSizeError", "The radius provided is negative.");
		path.ellipse(x, y, radiusX, radiusY, rotation, startAngle, endAngle, anticlockwise);
	}

	public function rect(x:Float, y:Float, w:Float, h:Float)
		path.rect(x, y, w, h);

	// radii: a number, or one to four numbers or {x, y} points (upper left first, clockwise)
	public function roundRect(x:Float, y:Float, w:Float, h:Float, ?radii:Dynamic)
		Path2D.roundRectInto(path, x, y, w, h, radii);

	@:noCompletion public static function roundRectInto(path:Path, x:Float, y:Float, w:Float, h:Float, radii:Dynamic) {
		var list:Array<Dynamic> = radii == null ? [0.0] : Std.isOfType(radii, Array) ? radii : [radii];
		if (list.length < 1 || list.length > 4)
			throw new DOMException("RangeError", list.length + " radii provided. Between one and four radii are necessary.");
		var rx = [], ry = [];
		for (r in list) {
			var px:Float, py:Float;
			if (Std.isOfType(r, Float) || Std.isOfType(r, Int)) {
				px = py = (r : Float);
			} else {
				px = Reflect.field(r, "x") ?? 0.0;
				py = Reflect.field(r, "y") ?? 0.0;
			}
			if (!Math.isFinite(px) || !Math.isFinite(py)) return;
			if (px < 0 || py < 0) throw new DOMException("RangeError", "A radius provided is negative.");
			rx.push(px);
			ry.push(py);
		}
		// (CSS's order: one for all; two: upper left and lower right, the others; three; four)
		var i = switch rx.length {
			case 1: [0, 0, 0, 0];
			case 2: [0, 1, 0, 1];
			case 3: [0, 1, 2, 1];
			case _: [0, 1, 2, 3];
		}
		path.roundRectXY(x, y, w, h, rx[i[0]], ry[i[0]], rx[i[1]], ry[i[1]], rx[i[2]], ry[i[2]], rx[i[3]], ry[i[3]]);
	}
}

// An error as the browser's DOMException: a name (IndexSizeError,
// InvalidStateError, SyntaxError, NotSupportedError...) and a message
class DOMException extends haxe.Exception {
	public final name:String;

	public function new(name:String, message:String) {
		super(message);
		this.name = name;
	}
}
