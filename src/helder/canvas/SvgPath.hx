package helder.canvas;

// SVG's path data (`M10 10 h 80 a 5 5 0 0 1 5 5 z`...) added to a Path:
// moves, lines, cubic and quadratic curves (their smooth forms too),
// elliptical arcs (as cubic curves, F.6's endpoint parameters), closes;
// an error ends it, what came before kept, as SVG says. Path2D's string
// constructor, helder.ui's Svg.
class SvgPath {
	public static function parse(d:String, p:Path) {
		var i = 0, n = d.length;
		var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
		// the last control point (for S and T) and what the last command was
		var cx = 0.0, cy = 0.0, last = " ".code;
		inline function code(k:Int):Int
			return StringTools.fastCodeAt(d, k);
		function skip()
			while (i < n && (code(i) == " ".code || code(i) == ",".code || code(i) == "\t".code || code(i) == "\n".code || code(i) == "\r".code
				|| code(i) == 12))
				i++;
		function number():Float {
			skip();
			var start = i;
			if (i < n && (code(i) == "+".code || code(i) == "-".code)) i++;
			var dot = false, digits = false;
			while (i < n) {
				var c = code(i);
				if (c >= "0".code && c <= "9".code) {
					digits = true;
					i++;
				} else if (c == ".".code && !dot) {
					dot = true;
					i++;
				} else
					break;
			}
			if (!digits) {
				i = start;
				return Math.NaN;
			}
			if (i < n && (code(i) == "e".code || code(i) == "E".code)) {
				var j = i + 1;
				if (j < n && (code(j) == "+".code || code(j) == "-".code)) j++;
				if (j < n && code(j) >= "0".code && code(j) <= "9".code) {
					i = j;
					while (i < n && code(i) >= "0".code && code(i) <= "9".code)
						i++;
				}
			}
			return Std.parseFloat(d.substring(start, i));
		}
		function flag():Float {
			skip();
			if (i < n && (code(i) == "0".code || code(i) == "1".code)) return code(i++) - "0".code;
			return Math.NaN;
		}
		var cmd = 0;
		while (true) {
			skip();
			if (i >= n) break;
			var c = code(i);
			var isCmd = (c >= "A".code && c <= "Z".code) || (c >= "a".code && c <= "z".code);
			if (isCmd) {
				cmd = c;
				i++;
			} else if (cmd == 0) break;
			else if (cmd == "M".code) cmd = "L".code;
			else if (cmd == "m".code) cmd = "l".code;
			else if (cmd == "Z".code || cmd == "z".code) break;
			// (the first command a move)
			if (last == " ".code && cmd != "M".code && cmd != "m".code) break;
			var rel = cmd >= "a".code;
			var ox = rel ? x : 0.0, oy = rel ? y : 0.0;
			switch cmd {
				case "M".code | "m".code:
					var a = number(), b = number();
					if (Math.isNaN(b) || Math.isNaN(a)) break;
					x = sx = ox + a;
					y = sy = oy + b;
					p.moveTo(x, y);
				case "L".code | "l".code:
					var a = number(), b = number();
					if (Math.isNaN(b) || Math.isNaN(a)) break;
					x = ox + a;
					y = oy + b;
					p.lineTo(x, y);
				case "H".code | "h".code:
					var a = number();
					if (Math.isNaN(a)) break;
					x = ox + a;
					p.lineTo(x, y);
				case "V".code | "v".code:
					var a = number();
					if (Math.isNaN(a)) break;
					y = oy + a;
					p.lineTo(x, y);
				case "C".code | "c".code | "S".code | "s".code:
					var x1, y1;
					if (cmd == "S".code || cmd == "s".code) {
						var smooth = last == "C".code || last == "c".code || last == "S".code || last == "s".code;
						x1 = smooth ? 2 * x - cx : x;
						y1 = smooth ? 2 * y - cy : y;
					} else {
						x1 = ox + number();
						y1 = oy + number();
					}
					var x2 = ox + number(), y2 = oy + number(), ex = ox + number(), ey = oy + number();
					if (Math.isNaN(x1 + y1 + x2 + y2 + ex + ey)) break;
					p.cubicTo(x1, y1, x2, y2, ex, ey);
					cx = x2;
					cy = y2;
					x = ex;
					y = ey;
				case "Q".code | "q".code | "T".code | "t".code:
					var qx, qy;
					if (cmd == "T".code || cmd == "t".code) {
						var smooth = last == "Q".code || last == "q".code || last == "T".code || last == "t".code;
						qx = smooth ? 2 * x - cx : x;
						qy = smooth ? 2 * y - cy : y;
					} else {
						qx = ox + number();
						qy = oy + number();
					}
					var ex = ox + number(), ey = oy + number();
					if (Math.isNaN(qx + qy + ex + ey)) break;
					p.quadTo(qx, qy, ex, ey);
					cx = qx;
					cy = qy;
					x = ex;
					y = ey;
				case "A".code | "a".code:
					var rx = number(), ry = number(), angle = number(), large = flag(), sweep = flag(), ex = ox + number(), ey = oy + number();
					if (Math.isNaN(rx + ry + angle + large + sweep + ex + ey)) break;
					arc(p, x, y, rx, ry, angle, large == 1, sweep == 1, ex, ey);
					x = ex;
					y = ey;
				case "Z".code | "z".code:
					p.close();
					x = sx;
					y = sy;
				case _:
					break;
			}
			last = cmd;
		}
	}

	// an elliptical arc from (x1, y1) to (x2, y2) by SVG's endpoint parameters (F.6)
	public static function arc(p:Path, x1:Float, y1:Float, rx:Float, ry:Float, angle:Float, large:Bool, sweep:Bool, x2:Float, y2:Float) {
		if (x1 == x2 && y1 == y2) return;
		rx = Math.abs(rx);
		ry = Math.abs(ry);
		if (rx == 0 || ry == 0) {
			p.lineTo(x2, y2);
			return;
		}
		var phi = angle * Math.PI / 180, cos = Math.cos(phi), sin = Math.sin(phi);
		var dx = (x1 - x2) / 2, dy = (y1 - y2) / 2;
		var x1p = cos * dx + sin * dy, y1p = -sin * dx + cos * dy;
		var lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
		if (lambda > 1) {
			var s = Math.sqrt(lambda);
			rx *= s;
			ry *= s;
		}
		var num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
		var den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
		var co = Math.sqrt(Math.max(0, num / den)) * (large == sweep ? -1 : 1);
		var cxp = co * rx * y1p / ry, cyp = -co * ry * x1p / rx;
		var cx = cos * cxp - sin * cyp + (x1 + x2) / 2, cy = sin * cxp + cos * cyp + (y1 + y2) / 2;
		inline function ang(ux:Float, uy:Float, vx:Float, vy:Float):Float
			return Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
		var t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
		var dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry);
		if (!sweep && dt > 0) dt -= 2 * Math.PI;
		if (sweep && dt < 0) dt += 2 * Math.PI;
		var pieces = Std.int(Math.ceil(Math.abs(dt) / (Math.PI / 2) - 1e-9));
		if (pieces < 1) pieces = 1;
		var step = dt / pieces, k = 4 / 3 * Math.tan(step / 4);
		var t = t1;
		for (j in 0...pieces) {
			var c1 = Math.cos(t), s1 = Math.sin(t), c2 = Math.cos(t + step), s2 = Math.sin(t + step);
			var ax = c1 - k * s1, ay = s1 + k * c1, bx = c2 + k * s2, by = s2 - k * c2;
			inline function px(u:Float, v:Float):Float
				return cos * rx * u - sin * ry * v + cx;
			inline function py(u:Float, v:Float):Float
				return sin * rx * u + cos * ry * v + cy;
			var last = j == pieces - 1;
			p.cubicTo(px(ax, ay), py(ax, ay), px(bx, by), py(bx, by), last ? x2 : px(c2, s2), last ? y2 : py(c2, s2));
			t += step;
		}
	}
}
