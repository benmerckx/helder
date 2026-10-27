package helder.text;

import haxe.io.Bytes;
import haxe.ds.Vector;

// OpenType font variations of TrueType outlines: fvar's axes, avar's
// mappings of the normalized coordinates, and gvar's deltas, as the
// specification (and FreeType, HarfBuzz) applies them: each tuple's scalar
// from its region at the coordinates, its points' deltas (all of them, or
// those it names, the others inferred from their contour's neighbours:
// IUP), summed. A glyph's points are its outline's, or a composite's
// components' offsets, then four phantom points: the first two's x change
// the origin and the advance.
class Variations {
	public final axes:Array<{tag:String, min:Float, def:Float, max:Float}> = [];

	final data:Bytes;
	// per axis: avar's segment map (from, to pairs; empty: identity)
	final maps:Array<Array<Float>> = [];
	var axisCount = 0;
	var gvar = -1;
	var sharedTuples = 0;
	var glyphCount = 0;
	var longOffsets = false;
	var dataStart = 0;

	public function new(data:Bytes, fvar:Int, avar:Int, gvar:Int) {
		this.data = data;
		var arrays = u16(data, fvar + 4), count = u16(data, fvar + 8), size = u16(data, fvar + 10);
		for (i in 0...count) {
			var p = fvar + arrays + i * size;
			axes.push({tag: data.getString(p, 4), min: fixed(p + 4), def: fixed(p + 8), max: fixed(p + 12)});
		}
		axisCount = count;
		for (i in 0...count)
			maps.push([]);
		if (avar >= 0) {
			var n = u16(data, avar + 6), p = avar + 8;
			for (i in 0...n) {
				var pairs = u16(data, p);
				p += 2;
				var m = i < count ? maps[i] : [];
				for (k in 0...pairs) {
					m.push(f2dot14(p));
					m.push(f2dot14(p + 2));
					p += 4;
				}
			}
		}
		if (gvar >= 0) {
			this.gvar = gvar;
			sharedTuples = gvar + u32(data, gvar + 8);
			glyphCount = u16(data, gvar + 12);
			longOffsets = u16(data, gvar + 14) & 1 != 0;
			dataStart = gvar + u32(data, gvar + 16);
		}
	}

	// user values by axis tag (each axis's default when not given; clamped) as
	// normalized coordinates (-1 to 1), through avar, in F2DOT14's steps
	public function normalize(values:Map<String, Float>):Array<Float> {
		return [
			for (i in 0...axes.length) {
				var a = axes[i];
				var v = values.exists(a.tag) ? values.get(a.tag) : a.def;
				v = v < a.min ? a.min : v > a.max ? a.max : v;
				var n = v < a.def ? (a.def == a.min ? 0 : (v - a.def) / (a.def - a.min)) : v > a.def ? (a.max == a.def ? 0 : (v - a.def) / (a.max - a.def)) : 0.0;
				n = Math.fround(n * 16384) / 16384;
				var m = maps[i];
				if (m.length >= 4) {
					// (piecewise linear between the map's points)
					var k = 0;
					while (k + 2 < m.length && n > m[k + 2])
						k += 2;
					if (k + 2 >= m.length) n = m[k + 1] else {
						var x0 = m[k], y0 = m[k + 1], x1 = m[k + 2], y1 = m[k + 3];
						n = n <= x0 ? y0 : x1 == x0 ? y1 : y0 + (n - x0) * (y1 - y0) / (x1 - x0);
					}
					n = Math.fround(n * 16384) / 16384;
				}
				n;
			}
		];
	}

	// glyph g's deltas at coords, added to dx, dy: its n points (the
	// phantom points included, last); xs, ys and ends (each contour's last
	// point) for the inferred deltas of the outline's points (null for a
	// composite, or when only the phantom points are wanted)
	public function deltas(g:Int, coords:Array<Float>, n:Int, xs:Null<Vector<Float>>, ys:Null<Vector<Float>>, ends:Null<Array<Int>>,
			dx:Vector<Float>, dy:Vector<Float>) {
		if (gvar < 0 || g >= glyphCount) return;
		var off = offset(g), end = offset(g + 1);
		if (end <= off) return;
		var p = dataStart + off;
		var header = u16(data, p), count = header & 0x0FFF;
		var s = p + u16(data, p + 2), h = p + 4;
		var shared:Null<Array<Int>> = null;
		if (header & 0x8000 != 0) {
			shared = points(s);
			s = next;
		}
		var peak = new Vector<Float>(axisCount), start = new Vector<Float>(axisCount), stop = new Vector<Float>(axisCount);
		for (t in 0...count) {
			var size = u16(data, h), index = u16(data, h + 2);
			h += 4;
			if (index & 0x8000 != 0) {
				for (i in 0...axisCount)
					peak[i] = f2dot14(h + 2 * i);
				h += 2 * axisCount;
			} else {
				var q = sharedTuples + (index & 0x0FFF) * axisCount * 2;
				for (i in 0...axisCount)
					peak[i] = f2dot14(q + 2 * i);
			}
			var intermediate = index & 0x4000 != 0;
			if (intermediate) {
				for (i in 0...axisCount) {
					start[i] = f2dot14(h + 2 * i);
					stop[i] = f2dot14(h + 2 * (axisCount + i));
				}
				h += 4 * axisCount;
			}
			var at = s;
			s += size;
			var scalar = 1.0;
			for (i in 0...axisCount) {
				var pk = peak[i], v = i < coords.length ? coords[i] : 0.0;
				if (pk == 0 || v == pk) continue;
				if (intermediate) {
					var a = start[i], b = stop[i];
					// (an invalid region: no effect on this axis, as FreeType)
					if (a > pk || pk > b || (a < 0 && b > 0 && pk != 0)) continue;
					if (v < a || v > b) {
						scalar = 0;
						break;
					}
					scalar *= v < pk ? (v - a) / (pk - a) : (b - v) / (b - pk);
				} else {
					if (v == 0 || v < Math.min(0, pk) || v > Math.max(0, pk)) {
						scalar = 0;
						break;
					}
					scalar *= v / pk;
				}
			}
			if (scalar == 0) continue;
			var pts = shared;
			if (index & 0x2000 != 0) {
				pts = points(at);
				at = next;
			}
			var m = pts == null ? n : pts.length;
			var xd = values(at, m);
			var yd = values(next, m);
			if (pts == null) {
				for (i in 0...(m < n ? m : n)) {
					dx[i] += xd[i] * scalar;
					dy[i] += yd[i] * scalar;
				}
				continue;
			}
			// (the points it names; the outline's others inferred)
			var tx = new Vector<Float>(n), ty = new Vector<Float>(n), touched = new Vector<Bool>(n);
			for (i in 0...n) {
				tx[i] = ty[i] = 0;
				touched[i] = false;
			}
			for (k in 0...m) {
				var i = pts[k];
				if (i >= n) continue;
				tx[i] = xd[k];
				ty[i] = yd[k];
				touched[i] = true;
			}
			if (xs != null && ends != null) {
				var first = 0;
				for (e in ends) {
					infer(first, e, xs, tx, touched);
					infer(first, e, ys, ty, touched);
					first = e + 1;
				}
			}
			for (i in 0...n) {
				dx[i] += tx[i] * scalar;
				dy[i] += ty[i] * scalar;
			}
		}
	}

	// IUP: a contour's (first...last) untouched points' deltas on one axis
	// from the touched points before and after each (cyclically): beyond
	// both, the nearer's; between, interpolated; one touched point, its delta
	static function infer(first:Int, last:Int, cs:Vector<Float>, ds:Vector<Float>, touched:Vector<Bool>) {
		var any = -1;
		for (i in first...last + 1)
			if (touched[i]) {
				any = i;
				break;
			}
		if (any < 0) return;
		var i = any;
		do {
			// the next touched point after i
			var j = i == last ? first : i + 1;
			while (!touched[j])
				j = j == last ? first : j + 1;
			if (j == i) {
				// (one touched point: its delta everywhere)
				for (k in first...last + 1)
					if (!touched[k]) ds[k] = ds[i];
				return;
			}
			var c1 = cs[i], c2 = cs[j], d1 = ds[i], d2 = ds[j];
			var k = i == last ? first : i + 1;
			while (k != j) {
				var c = cs[k];
				ds[k] = if (c1 == c2) d1 == d2 ? d1 : 0 else if (c <= Math.min(c1, c2)) c1 < c2 ? d1 : d2 else if (c >= Math.max(c1, c2)) c1 > c2 ? d1 : d2 else d1
					+ (c - c1) * (d2 - d1) / (c2 - c1);
				k = k == last ? first : k + 1;
			}
			i = j;
		} while (i != any);
	}

	inline function offset(g:Int):Int
		return longOffsets ? u32(data, gvar + 20 + 4 * g) : 2 * u16(data, gvar + 20 + 2 * g);

	// (where the last packed run ended)
	var next = 0;

	// packed point numbers at p (null: all of them); next after them
	function points(p:Int):Null<Array<Int>> {
		var count = data.get(p++);
		if (count & 0x80 != 0) count = ((count & 0x7F) << 8) | data.get(p++);
		if (count == 0) {
			next = p;
			return null;
		}
		var out = [], last = 0;
		while (out.length < count) {
			var c = data.get(p++), words = c & 0x80 != 0, run = (c & 0x7F) + 1;
			for (k in 0...run) {
				if (out.length >= count) break;
				last += words ? u16(data, p) : data.get(p);
				p += words ? 2 : 1;
				out.push(last);
			}
		}
		next = p;
		return out;
	}

	// count packed deltas at p; next after them
	function values(p:Int, count:Int):Vector<Float> {
		var out = new Vector<Float>(count), i = 0;
		while (i < count) {
			var c = data.get(p++), run = (c & 0x3F) + 1;
			for (k in 0...run) {
				if (i >= count) break;
				if (c & 0xC0 == 0xC0) {
					out[i++] = u32(data, p);
					p += 4;
				} else if (c & 0x80 != 0) out[i++] = 0 else if (c & 0x40 != 0) {
					out[i++] = s16(data, p);
					p += 2;
				} else {
					var b = data.get(p++);
					out[i++] = b >= 128 ? b - 256 : b;
				}
			}
		}
		next = p;
		return out;
	}

	inline function fixed(p:Int):Float
		return u32(data, p) / 65536;

	inline function f2dot14(p:Int):Float
		return s16(data, p) / 16384;

	static inline function u16(b:Bytes, p:Int):Int
		return (b.get(p) << 8) | b.get(p + 1);

	static inline function s16(b:Bytes, p:Int):Int {
		var v = u16(b, p);
		return v >= 0x8000 ? v - 0x10000 : v;
	}

	static inline function u32(b:Bytes, p:Int):Int
		return (b.get(p) << 24) | (b.get(p + 1) << 16) | (b.get(p + 2) << 8) | b.get(p + 3);
}
