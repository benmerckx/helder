package hxmc.text;

import haxe.io.Bytes;

// The outlines of an OpenType font with a CFF table ('OTTO', .otf): its
// INDEXes and DICTs (the Adobe Compact Font Format, technical note #5176),
// the glyphs' Type 2 charstrings (note #5177) run into an Outline as lines
// and cubic curves, local and global subroutines with their biases, hints
// skipped; a CID-keyed font's glyphs each with their font DICT's private
// subroutines (FDSelect formats 0 and 3). Coordinates are in font units (the
// FontMatrix's scale to the head table's units per em applied), y up.
class Cff {
	final data:Bytes;
	final globalSubrs:Index;
	final charStrings:Index;
	// the local subroutines: one set, or per font DICT (CID-keyed)
	final localSubrs:Array<Null<Index>> = [];
	var fdSelect = -1;
	var fdSelectFormat = 0;
	// font units per charstring unit
	public var scale(default, null) = 1.0;
	public var glyphCount(get, never):Int;

	inline function get_glyphCount()
		return charStrings.count;

	// the CFF table at start; unitsPerEm: the head table's
	public function new(data:Bytes, start:Int, unitsPerEm:Int) {
		this.data = data;
		var hdrSize = data.get(start + 2);
		var names = new Index(data, start + hdrSize);
		var tops = new Index(data, names.after);
		var strings = new Index(data, tops.after);
		globalSubrs = new Index(data, strings.after);
		if (tops.count < 1) throw "Cff: no Top DICT";
		var top = dict(tops.start(0), tops.end(0));
		if (!top.exists(17)) throw "Cff: no CharStrings";
		if (top.exists(0x0C06) && top.get(0x0C06)[0] != 2) throw "Cff: not Type 2 charstrings";
		charStrings = new Index(data, start + Std.int(top.get(17)[0]));
		if (top.exists(0x0C07)) {
			var m = top.get(0x0C07);
			if (m[0] != 0) scale = m[0] * unitsPerEm;
			if (Math.abs(scale - 1) < 1e-6) scale = 1;
		}
		if (top.exists(0x0C1E)) {
			// CID-keyed: a private DICT per font DICT
			if (!top.exists(0x0C24) || !top.exists(0x0C25)) throw "Cff: a CID font without FDArray or FDSelect";
			var fds = new Index(data, start + Std.int(top.get(0x0C24)[0]));
			for (i in 0...fds.count)
				localSubrs.push(privateSubrs(start, dict(fds.start(i), fds.end(i))));
			fdSelect = start + Std.int(top.get(0x0C25)[0]);
			fdSelectFormat = data.get(fdSelect);
			if (fdSelectFormat != 0 && fdSelectFormat != 3) throw "Cff: FDSelect format " + fdSelectFormat;
		} else localSubrs.push(privateSubrs(start, top));
	}

	// a DICT's Private (size, offset): its local subroutines (Subrs, from the private DICT's start)
	function privateSubrs(start:Int, d:Map<Int, Array<Float>>):Null<Index> {
		if (!d.exists(18)) return null;
		var p = d.get(18), size = Std.int(p[0]), at = start + Std.int(p[1]);
		var pd = dict(at, at + size);
		return pd.exists(19) ? new Index(data, at + Std.int(pd.get(19)[0])) : null;
	}

	// the font DICT of a CID-keyed glyph
	function fdOf(g:Int):Int {
		if (fdSelect < 0) return 0;
		if (fdSelectFormat == 0) return data.get(fdSelect + 1 + g);
		var n = u16(fdSelect + 1);
		for (i in 0...n) {
			var r = fdSelect + 3 + 3 * i;
			if (g >= u16(r) && g < u16(r + 3)) return data.get(r + 2);
		}
		return 0;
	}

	// a DICT's operators (12 x: 0x0C00 | x) and their operands
	function dict(p:Int, end:Int):Map<Int, Array<Float>> {
		var m = new Map<Int, Array<Float>>();
		var ops:Array<Float> = [];
		while (p < end) {
			var b0 = data.get(p);
			if (b0 <= 21) {
				var op = b0;
				p++;
				if (b0 == 12) op = 0x0C00 | data.get(p++);
				m.set(op, ops);
				ops = [];
			} else if (b0 == 28) {
				ops.push(s16(p + 1));
				p += 3;
			} else if (b0 == 29) {
				ops.push((data.get(p + 1) << 24) | (data.get(p + 2) << 16) | (data.get(p + 3) << 8) | data.get(p + 4));
				p += 5;
			} else if (b0 == 30) {
				// a real: nibbles (0-9, ., E, E-, -, end)
				var s = new StringBuf();
				p++;
				var done = false;
				while (!done) {
					var b = data.get(p++);
					for (n in [b >> 4, b & 15]) {
						if (done) break;
						switch n {
							case 0xA: s.add(".");
							case 0xB: s.add("e");
							case 0xC: s.add("e-");
							case 0xE: s.add("-");
							case 0xF: done = true;
							case 0xD:
							case _: s.add(n);
						}
					}
				}
				var v = Std.parseFloat(s.toString());
				ops.push(Math.isNaN(v) ? 0 : v);
			} else if (b0 >= 32 && b0 <= 246) {
				ops.push(b0 - 139);
				p++;
			} else if (b0 >= 247 && b0 <= 250) {
				ops.push((b0 - 247) * 256 + data.get(p + 1) + 108);
				p += 2;
			} else if (b0 >= 251 && b0 <= 254) {
				ops.push(-(b0 - 251) * 256 - data.get(p + 1) - 108);
				p += 2;
			} else p++;
		}
		return m;
	}

	// the glyph's outline (font units, y up), through the transform
	public function outline(g:Int, out:Outline) {
		if (g < 0 || g >= charStrings.count) return;
		new Charstring(this, out, localSubrs[fdOf(g)]).run(charStrings.start(g), charStrings.end(g));
	}

	// the glyph's bounding box in font units (its points, control points too: xMin, yMin, xMax, yMax; all 0 when empty)
	public function bounds(g:Int):Array<Int> {
		var b = new Bounds();
		outline(g, b);
		return b.empty ? [0, 0, 0, 0] : [Math.floor(b.x0), Math.floor(b.y0), Math.ceil(b.x1), Math.ceil(b.y1)];
	}

	@:allow(hxmc.text) inline function byte(p:Int):Int
		return data.get(p);

	@:allow(hxmc.text) inline function u16(p:Int):Int
		return (data.get(p) << 8) | data.get(p + 1);

	@:allow(hxmc.text) inline function s16(p:Int):Int {
		var v = u16(p);
		return v >= 0x8000 ? v - 0x10000 : v;
	}

	@:allow(hxmc.text) function subr(local:Bool, i:Int, subrs:Null<Index>):Int {
		var x = local ? subrs : globalSubrs;
		if (x == null) throw "Cff: no subroutines";
		var n = i + bias(x.count);
		if (n < 0 || n >= x.count) throw "Cff: no subroutine " + n;
		return n;
	}

	@:allow(hxmc.text) function subrStart(local:Bool, n:Int, subrs:Null<Index>):Int
		return (local ? subrs : globalSubrs).start(n);

	@:allow(hxmc.text) function subrEnd(local:Bool, n:Int, subrs:Null<Index>):Int
		return (local ? subrs : globalSubrs).end(n);

	static inline function bias(count:Int):Int
		return count < 1240 ? 107 : count < 33900 ? 1131 : 32768;
}

// an INDEX: count objects, their data after the offsets (offSize bytes each, from 1)
private class Index {
	final data:Bytes;
	public final count:Int;
	final offSize:Int;
	final offsets:Int;
	final base:Int;
	public var after(default, null):Int;

	public function new(data:Bytes, p:Int) {
		this.data = data;
		count = (data.get(p) << 8) | data.get(p + 1);
		if (count == 0) {
			offSize = 0;
			offsets = base = p + 2;
			after = p + 2;
			return;
		}
		offSize = data.get(p + 2);
		offsets = p + 3;
		base = offsets + (count + 1) * offSize - 1;
		after = base + offset(count);
	}

	function offset(i:Int):Int {
		var v = 0, q = offsets + i * offSize;
		for (k in 0...offSize)
			v = (v << 8) | data.get(q + k);
		return v;
	}

	public inline function start(i:Int):Int
		return base + offset(i);

	public inline function end(i:Int):Int
		return base + offset(i + 1);
}

// a Type 2 charstring's interpreter, drawing into an Outline
private class Charstring {
	final cff:Cff;
	final out:Outline;
	final subrs:Null<Index>;
	final stack:Array<Float> = [];
	var x = 0.0;
	var y = 0.0;
	var stems = 0;
	var open = false;
	var widthDone = false;
	var ended = false;
	var depth = 0;

	public function new(cff:Cff, out:Outline, subrs:Null<Index>) {
		this.cff = cff;
		this.out = out;
		this.subrs = subrs;
	}

	inline function k():Float
		return cff.scale;

	function moveTo(dx:Float, dy:Float) {
		if (open) out.close();
		x += dx;
		y += dy;
		out.moveTo(x * k(), y * k());
		open = true;
	}

	function lineTo(dx:Float, dy:Float) {
		x += dx;
		y += dy;
		out.lineTo(x * k(), y * k());
	}

	function curveTo(dx1:Float, dy1:Float, dx2:Float, dy2:Float, dx3:Float, dy3:Float) {
		var x1 = x + dx1, y1 = y + dy1;
		var x2 = x1 + dx2, y2 = y1 + dy2;
		x = x2 + dx3;
		y = y2 + dy3;
		out.cubicTo(x1 * k(), y1 * k(), x2 * k(), y2 * k(), x * k(), y * k());
	}

	// the first stack-clearing operator may carry the advance width first: dropped
	function width(even:Bool) {
		if (widthDone) return;
		widthDone = true;
		if ((stack.length % 2 == 1) == even) stack.shift();
	}

	function stemHints() {
		width(true);
		stems += stack.length >> 1;
		stack.resize(0);
	}

	public function run(p:Int, end:Int) {
		if (++depth > 10) throw "Cff: subroutines nested too deep";
		while (p < end && !ended) {
			var b0 = cff.byte(p);
			if (b0 >= 32 || b0 == 28) {
				// an operand
				if (b0 == 28) {
					stack.push(cff.s16(p + 1));
					p += 3;
				} else if (b0 <= 246) {
					stack.push(b0 - 139);
					p++;
				} else if (b0 <= 250) {
					stack.push((b0 - 247) * 256 + cff.byte(p + 1) + 108);
					p += 2;
				} else if (b0 <= 254) {
					stack.push(-(b0 - 251) * 256 - cff.byte(p + 1) - 108);
					p += 2;
				} else {
					// 16.16 fixed
					var v = (cff.byte(p + 1) << 24) | (cff.byte(p + 2) << 16) | (cff.byte(p + 3) << 8) | cff.byte(p + 4);
					stack.push(v / 65536);
					p += 5;
				}
				continue;
			}
			p++;
			var s = stack;
			switch b0 {
				case 1 | 3 | 18 | 23: // hstem, vstem, hstemhm, vstemhm
					stemHints();
				case 19 | 20: // hintmask, cntrmask: vstems first, then the mask's bytes
					stemHints();
					p += (stems + 7) >> 3;
				case 21: // rmoveto
					width(true);
					moveTo(s[0], s[1]);
					s.resize(0);
				case 22: // hmoveto
					width(false);
					moveTo(s[0], 0);
					s.resize(0);
				case 4: // vmoveto
					width(false);
					moveTo(0, s[0]);
					s.resize(0);
				case 5: // rlineto
					var i = 0;
					while (i + 1 < s.length) {
						lineTo(s[i], s[i + 1]);
						i += 2;
					}
					s.resize(0);
				case 6 | 7: // hlineto, vlineto: alternating
					var horizontal = b0 == 6;
					for (v in s) {
						if (horizontal) lineTo(v, 0) else lineTo(0, v);
						horizontal = !horizontal;
					}
					s.resize(0);
				case 8: // rrcurveto
					var i = 0;
					while (i + 5 < s.length) {
						curveTo(s[i], s[i + 1], s[i + 2], s[i + 3], s[i + 4], s[i + 5]);
						i += 6;
					}
					s.resize(0);
				case 24: // rcurveline
					var i = 0;
					while (i + 5 < s.length - 2) {
						curveTo(s[i], s[i + 1], s[i + 2], s[i + 3], s[i + 4], s[i + 5]);
						i += 6;
					}
					lineTo(s[i], s[i + 1]);
					s.resize(0);
				case 25: // rlinecurve
					var i = 0;
					while (i + 1 < s.length - 6) {
						lineTo(s[i], s[i + 1]);
						i += 2;
					}
					curveTo(s[i], s[i + 1], s[i + 2], s[i + 3], s[i + 4], s[i + 5]);
					s.resize(0);
				case 26: // vvcurveto: dx1? {dya dxb dyb dyc}+
					var i = 0, dx1 = 0.0;
					if (s.length % 4 == 1) {
						dx1 = s[0];
						i = 1;
					}
					while (i + 3 < s.length) {
						curveTo(dx1, s[i], s[i + 1], s[i + 2], 0, s[i + 3]);
						dx1 = 0;
						i += 4;
					}
					s.resize(0);
				case 27: // hhcurveto: dy1? {dxa dxb dyb dxc}+
					var i = 0, dy1 = 0.0;
					if (s.length % 4 == 1) {
						dy1 = s[0];
						i = 1;
					}
					while (i + 3 < s.length) {
						curveTo(s[i], dy1, s[i + 1], s[i + 2], s[i + 3], 0);
						dy1 = 0;
						i += 4;
					}
					s.resize(0);
				case 30 | 31: // vhcurveto, hvcurveto: alternating, a last df
					var horizontal = b0 == 31;
					var i = 0;
					while (i + 3 < s.length) {
						var last = s.length - i == 5 ? s[i + 4] : 0.0;
						if (horizontal) curveTo(s[i], 0, s[i + 1], s[i + 2], last, s[i + 3]) else curveTo(0, s[i], s[i + 1], s[i + 2], s[i + 3], last);
						horizontal = !horizontal;
						i += 4;
					}
					s.resize(0);
				case 10 | 29: // callsubr, callgsubr
					var local = b0 == 10;
					var n = cff.subr(local, Std.int(s.pop()), subrs);
					run(cff.subrStart(local, n, subrs), cff.subrEnd(local, n, subrs));
				case 11: // return
					depth--;
					return;
				case 14: // endchar
					width(true);
					if (open) out.close();
					open = false;
					ended = true;
					s.resize(0);
				case 12:
					var op = cff.byte(p++);
					switch op {
						case 35: // flex: two curves, a flex depth
							curveTo(s[0], s[1], s[2], s[3], s[4], s[5]);
							curveTo(s[6], s[7], s[8], s[9], s[10], s[11]);
						case 34: // hflex
							var y0 = y;
							curveTo(s[0], 0, s[1], s[2], s[3], 0);
							curveTo(s[4], 0, s[5], y0 - y, s[6], 0);
						case 36: // hflex1
							var y0 = y;
							curveTo(s[0], s[1], s[2], s[3], s[4], 0);
							curveTo(s[5], 0, s[6], s[7], s[8], y0 - y - s[7]);
						case 37: // flex1: the last point's other coordinate back to the start's
							var x0 = x, y0 = y;
							var dx = s[0] + s[2] + s[4] + s[6] + s[8], dy = s[1] + s[3] + s[5] + s[7] + s[9];
							curveTo(s[0], s[1], s[2], s[3], s[4], s[5]);
							if (Math.abs(dx) > Math.abs(dy)) curveTo(s[6], s[7], s[8], s[9], s[10], y0 - y - s[7] - s[9])
							else curveTo(s[6], s[7], s[8], s[9], x0 - x - s[6] - s[8], s[10]);
						case _:
					}
					s.resize(0);
				case _:
					s.resize(0);
			}
		}
		depth--;
		if (depth == 0 && open) {
			out.close();
			open = false;
		}
	}
}

// the extent of an outline's points
private class Bounds implements Outline {
	public var x0 = Math.POSITIVE_INFINITY;
	public var y0 = Math.POSITIVE_INFINITY;
	public var x1 = Math.NEGATIVE_INFINITY;
	public var y1 = Math.NEGATIVE_INFINITY;
	public var empty(get, never):Bool;

	public function new() {}

	inline function get_empty()
		return x0 > x1;

	inline function add(x:Float, y:Float) {
		if (x < x0) x0 = x;
		if (x > x1) x1 = x;
		if (y < y0) y0 = y;
		if (y > y1) y1 = y;
	}

	public function moveTo(x:Float, y:Float)
		add(x, y);

	public function lineTo(x:Float, y:Float)
		add(x, y);

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float) {
		add(cx, cy);
		add(x, y);
	}

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float) {
		add(c1x, c1y);
		add(c2x, c2y);
		add(x, y);
	}

	public function close() {}
}
