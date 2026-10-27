package helder.text;

import haxe.ds.Vector;
import haxe.io.Bytes;
import helder.scoped.*;

// Rasterizer's algorithm on scoped memory, for GlyphAtlas: a path (GlyphPath's
// commands, in pixels) rasterized into a coverage bitmap, its accumulation
// buffer in the call's scope, so drawing a glyph allocates nothing on the GC
// heap. The same sums in the same order as Rasterizer, so the same pixels.
// (Rasterizer keeps its own buffer: it draws across calls, at any size.)
@:build(helder.scoped.Scoped.build())
class Coverage {
	public static inline var MOVE = 0;
	public static inline var LINE = 1;
	public static inline var QUAD = 2;
	public static inline var CUBIC = 3;
	public static inline var CLOSE = 4;

	// the path's n commands' coverage, w x h, as bytes into dst at offset,
	// rows of dstStride
	@:scoped public static function fill(path:Vector<Float>, n:Int, w:Int, h:Int, dst:Bytes, offset:Int, dstStride:Int) {
		var stride = w + 2;
		var acc = Scope.slice(Float, stride * h + 2);
		draw(path, n, acc, w, h);
		for (y in 0...h) {
			var sum = 0.0, row = y * stride, o = offset + y * dstStride;
			for (x in 0...w) {
				sum += acc[row + x];
				var c = Math.abs(sum);
				dst.set(o + x, c >= 1 ? 255 : Std.int(c * 255 + 0.5));
			}
		}
	}

	// the same blurred into dst: grown by pad each side, a Gaussian of
	// standard deviation sigma across, then down (its weights each pixel's
	// share of the curve, summing to one)
	@:scoped public static function fillBlurred(path:Vector<Float>, n:Int, w:Int, h:Int, pad:Int, sigma:Float, dst:Bytes, offset:Int, dstStride:Int) {
		var stride = w + 2;
		var acc = Scope.slice(Float, stride * h + 2);
		draw(path, n, acc, w, h);
		var sharp = Scope.slice(U8, w * h);
		for (y in 0...h) {
			var sum = 0.0, row = y * stride;
			for (x in 0...w) {
				sum += acc[row + x];
				var c = Math.abs(sum);
				sharp[y * w + x] = c >= 1 ? 255 : Std.int(c * 255 + 0.5);
			}
		}
		var weights = Scope.slice(Float, 2 * pad + 1), total = 0.0;
		for (i in 0...weights.length) {
			var d = i - pad;
			weights[i] = Math.exp(-d * d / (2 * sigma * sigma));
			total += weights[i];
		}
		for (i in 0...weights.length)
			weights[i] /= total;
		var bw = w + 2 * pad, bh = h + 2 * pad;
		// (across: each source row into the wider one)
		var across = Scope.slice(Float, bw * h);
		for (y in 0...h)
			for (x in 0...bw) {
				var v = 0.0;
				for (i in 0...weights.length) {
					var sx = x - pad + i - pad;
					if (sx >= 0 && sx < w) v += weights[i] * (sharp[y * w + sx] : Int);
				}
				across[y * bw + x] = v;
			}
		// (down: into dst, taller by pad each side)
		for (y in 0...bh)
			for (x in 0...bw) {
				var v = 0.0;
				for (i in 0...weights.length) {
					var sy = y - pad + i - pad;
					if (sy >= 0 && sy < h) v += weights[i] * across[sy * bw + x];
				}
				var c = Std.int(v + 0.5);
				dst.set(offset + y * dstStride + x, c > 255 ? 255 : c);
			}
	}

	// (the commands into acc, as Rasterizer's moveTo, lineTo... draw them)
	@:scoped static function draw(path:Vector<Float>, n:Int, acc:Slice<Float>, width:Int, height:Int) {
		var px = 0.0, py = 0.0, sx = 0.0, sy = 0.0, k = 0;
		while (k < n) {
			switch Std.int(path[k]) {
				case MOVE:
					px = sx = path[k + 1];
					py = sy = path[k + 2];
					k += 3;
				case LINE:
					var nx = path[k + 1], ny = path[k + 2];
					line(acc, width, height, px, py, nx, ny);
					px = nx;
					py = ny;
					k += 3;
				case QUAD:
					var x1 = path[k + 1], y1 = path[k + 2], x2 = path[k + 3], y2 = path[k + 4];
					var devx = px - 2 * x1 + x2, devy = py - 2 * y1 + y2;
					var devsq = devx * devx + devy * devy;
					if (devsq < 0.333) {
						line(acc, width, height, px, py, x2, y2);
					} else {
						var m = 1 + Math.floor(Math.sqrt(Math.sqrt(3 * devsq)));
						var lx = px, ly = py;
						for (i in 1...m + 1) {
							var t = i / m, u = 1 - t;
							var qx = u * u * px + 2 * u * t * x1 + t * t * x2, qy = u * u * py + 2 * u * t * y1 + t * t * y2;
							line(acc, width, height, lx, ly, qx, qy);
							lx = qx;
							ly = qy;
						}
					}
					px = x2;
					py = y2;
					k += 5;
				case CUBIC:
					var x1 = path[k + 1], y1 = path[k + 2], x2 = path[k + 3], y2 = path[k + 4], x3 = path[k + 5], y3 = path[k + 6];
					var ax = px - 2 * x1 + x2, ay = py - 2 * y1 + y2, bx = x1 - 2 * x2 + x3, by = y1 - 2 * y2 + y3;
					var dev = Math.sqrt(Math.max(ax * ax + ay * ay, bx * bx + by * by));
					var m = 1 + Math.floor(Math.sqrt(dev * 0.75 / 0.2));
					var lx = px, ly = py;
					for (i in 1...m + 1) {
						var t = i / m, u = 1 - t;
						var a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
						var qx = a * px + b * x1 + c * x2 + d * x3, qy = a * py + b * y1 + c * y2 + d * y3;
						line(acc, width, height, lx, ly, qx, qy);
						lx = qx;
						ly = qy;
					}
					px = x3;
					py = y3;
					k += 7;
				case _:
					if (px != sx || py != sy) line(acc, width, height, px, py, sx, sy);
					px = sx;
					py = sy;
					k++;
			}
		}
	}

	// (Rasterizer.line: clipped to the columns, a part left of them at the left edge)
	@:scoped static function line(acc:Slice<Float>, width:Int, height:Int, x0:Float, y0:Float, x1:Float, y1:Float) {
		if (Math.abs(y0 - y1) <= 1e-9) return;
		if (x0 >= 0 && x1 >= 0 && x0 <= width && x1 <= width) {
			scan(acc, width, height, x0, y0, x1, y1);
			return;
		}
		if (x0 >= width && x1 >= width) return;
		if (x0 <= 0 && x1 <= 0) {
			scan(acc, width, height, 0, y0, 0, y1);
			return;
		}
		var edge = (x0 < 0 || x1 < 0) && !((x0 - 0) * (x1 - 0) > 0) ? 0.0 : width;
		var t = (edge - x0) / (x1 - x0), ym = y0 + (y1 - y0) * t;
		line(acc, width, height, x0, y0, edge, ym);
		line(acc, width, height, edge, ym, x1, y1);
	}

	// (Rasterizer.scan: each row's exact area)
	@:scoped static function scan(acc:Slice<Float>, width:Int, height:Int, x0:Float, y0:Float, x1:Float, y1:Float) {
		if (Math.abs(y0 - y1) <= 1e-9) return;
		var stride = width + 2;
		var dir = 1.0;
		if (y0 > y1) {
			dir = -1;
			var t = x0;
			x0 = x1;
			x1 = t;
			t = y0;
			y0 = y1;
			y1 = t;
		}
		var dxdy = (x1 - x0) / (y1 - y0);
		var x = x0;
		if (y0 < 0) x -= y0 * dxdy;
		var yStart = y0 < 0 ? 0 : Math.floor(y0), yEnd = Std.int(Math.min(height, Math.ceil(y1)));
		for (y in yStart...yEnd) {
			var row = y * stride;
			var dy = Math.min(y + 1, y1) - Math.max(y, y0);
			var xnext = x + dxdy * dy;
			var d = dy * dir;
			var a = x < xnext ? x : xnext, b = x < xnext ? xnext : x;
			if (a < 0) a = 0;
			if (b < 0) b = 0;
			if (a > width) a = width;
			if (b > width) b = width;
			var a0f = Math.floor(a), a0 = Std.int(a0f), b1c = Math.ceil(b), b1 = Std.int(b1c);
			if (b1 <= a0 + 1) {
				var xm = 0.5 * (a + b) - a0f;
				acc[row + a0] += d - d * xm;
				acc[row + a0 + 1] += d * xm;
			} else {
				var s = 1 / (b - a);
				var af = a - a0f;
				var c0 = 0.5 * s * (1 - af) * (1 - af);
				var bf = b - b1c + 1;
				var cm = 0.5 * s * bf * bf;
				acc[row + a0] += d * c0;
				if (b1 == a0 + 2) acc[row + a0 + 1] += d * (1 - c0 - cm) else {
					var c1 = s * (1.5 - af);
					acc[row + a0 + 1] += d * (c1 - c0);
					for (xi in a0 + 2...b1 - 1)
						acc[row + xi] += d * s;
					var c2 = c1 + (b1 - a0 - 3) * s;
					acc[row + b1 - 1] += d * (1 - c2 - cm);
				}
				acc[row + b1] += d * cm;
			}
			x = xnext;
		}
	}
}
