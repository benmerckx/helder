package helder.pdf;

import haxe.io.Bytes;
import haxe.ds.Vector;

// JPEG 2000 (ITU-T T.800, Part 1) for JPXDecode images, ported from
// leanpdf's core/jpx.ts, jpx/t1.ts and jpx/dwt.ts: JP2 files and bare
// codestreams; tiles decoded one at a time into the 8-bit output (the
// working memory the output and one tile's coefficients); reduce drops
// the highest resolution levels without decoding their code-blocks. Never
// throws on bad data: damaged data gives what was decoded before it.
typedef JpxImage = {
	width:Int,
	height:Int,
	// samples a pixel, palette expanded (an alpha channel among them when alpha >= 0)
	components:Int,
	// interleaved 8-bit samples; YCbCr and the component transforms already RGB
	data:Bytes,
	// "gray", "rgb", "cmyk" or null (the JP2 header's colr)
	colorSpace:Null<String>,
	alpha:Int,
	// resolution levels in the codestream (for choosing reduce)
	levels:Int,
}

private class Cod {
	public var levels = 0;
	public var xcb = 0;
	public var ycb = 0;
	public var style = 0;
	public var rev = false;
	// PPx | PPy << 4 per resolution level; null: maximal precincts
	public var pp:Null<Bytes> = null;
	public var sop = false;
	public var eph = false;
	public var order = 0;
	public var layers = 0;
	public var mct = 0;

	public function new() {}
}

private class Qcd {
	public var kind = 0;
	public var guard = 0;
	public var v:Array<Int> = [];

	public function new() {}
}

private class Params {
	public var cod:Null<Cod> = null;
	public final coc = new Map<Int, Cod>();
	public var qcd:Null<Qcd> = null;
	public final qcc = new Map<Int, Qcd>();
	public final rgn = new Map<Int, Int>();
	// RSpoc, CSpoc, LYEpoc, REpoc, CEpoc, Ppoc
	public final poc:Array<Array<Int>> = [];
	public final ppt:Array<{z:Int, b:Bytes}> = [];

	public function new() {}
}

private class Comp {
	public final prec:Int;
	public final sgnd:Bool;
	public final dx:Int;
	public final dy:Int;

	public function new(prec, sgnd, dx, dy) {
		this.prec = prec;
		this.sgnd = sgnd;
		this.dx = dx;
		this.dy = dy;
	}
}

private class Siz {
	public var x0 = 0;
	public var y0 = 0;
	public var x1 = 0;
	public var y1 = 0;
	public var tw = 0;
	public var th = 0;
	public var tx0 = 0;
	public var ty0 = 0;
	public var ntx = 0;
	public var nty = 0;
	public final comps:Array<Comp> = [];

	public function new() {}
}

// a tile-part: its tile, header markers [h0, h1), data [d0, d1), index in the codestream
private typedef Part = {t:Int, h0:Int, h1:Int, d0:Int, d1:Int, i:Int};

private class Header {
	public final siz:Siz;
	public final main:Params;
	public final parts:Array<Part> = [];
	public var ppm:Null<Array<Bytes>> = null;

	public function new(siz, main) {
		this.siz = siz;
		this.main = main;
	}
}

private class Chan {
	public final c:Int;
	public final pal:Null<Bytes>;
	public final bits:Int;

	public function new(c, pal, bits) {
		this.c = c;
		this.pal = pal;
		this.bits = bits;
	}
}

// packet header bits: a 0xFF byte is followed by one of 7 bits
private class Bits {
	public final d:Bytes;
	public final e:Int;
	public var p = 0;
	var b = 0;
	var n = 0;

	public function new(d:Bytes) {
		this.d = d;
		e = d.length;
	}

	// (ones past the end, where p keeps counting: p > e when the data ran out)
	public function bit():Int {
		if (n == 0) {
			n = b == 0xff ? 7 : 8;
			b = p < e ? d.get(p) : 0x7f;
			p++;
		}
		return (b >> --n) & 1;
	}

	public function bits(k:Int):Int {
		var v = 0;
		while (k-- > 0)
			v = v * 2 + bit();
		return v;
	}

	public function align() {
		if (b == 0xff) p++;
		b = n = 0;
	}
}

// a tag tree (B.10.2) over a grid of code-blocks: each node the minimum of its children
private class TagTree {
	public final v:Vector<Int>;
	final lo:Vector<Int>;
	final up:Vector<Int>;
	static final STACK = new Vector<Int>(64, 0);

	public function new(w:Int, h:Int) {
		var dims = [], n = 0, lw = w, lh = h;
		while (true) {
			dims.push(n);
			dims.push(lw);
			dims.push(lh);
			n += lw * lh;
			if (lw * lh <= 1) break;
			lw = (lw + 1) >> 1;
			lh = (lh + 1) >> 1;
		}
		up = new Vector<Int>(n, -1);
		var l = 0;
		while (l + 3 < dims.length) {
			var o = dims[l], lw = dims[l + 1], lh = dims[l + 2], po = dims[l + 3], pw = dims[l + 4];
			for (y in 0...lh)
				for (x in 0...lw)
					up[o + y * lw + x] = po + (y >> 1) * pw + (x >> 1);
			l += 3;
		}
		v = new Vector<Int>(n, 0x7fffffff);
		lo = new Vector<Int>(n, 0);
	}

	// toward leaf i's value until it is known or reaches thr: 1 when below thr
	public function decode(b:Bits, i:Int, thr:Int):Int {
		var n = 0, j = i;
		while (j >= 0 && n < 64) {
			STACK[n++] = j;
			j = up[j];
		}
		var low = 0;
		while (n-- > 0) {
			var j = STACK[n];
			if (low > lo[j]) lo[j] = low else low = lo[j];
			while (low < thr && low < v[j]) {
				if (b.bit() != 0) v[j] = low else low++;
			}
			lo[j] = low;
		}
		return v[i] < thr ? 1 : 0;
	}
}

// a code-block: zero bit-planes, Lblock, coding passes so far, [offset, length, segment] each contribution
private class Blk {
	public var z:Int;
	public var lb = 3;
	public var n = 0;
	public final ch:Array<Int> = [];

	public function new(z) {
		this.z = z;
	}
}

private class Band {
	public var x0 = 0;
	public var y0 = 0;
	public var x1 = 0;
	public var y1 = 0;
	// tier 1's orientation: 0 LL and LH, 1 HL, 2 HH
	public var o = 0;
	public var ox = 0;
	public var oy = 0;
	public var xcb = 0;
	public var ycb = 0;
	public var bx0 = 0;
	public var by0 = 0;
	public var nbx = 0;
	public var nby = 0;
	public var blocks:Vector<Null<Blk>>;
	public var mb = 0;
	public var step = 0.0;

	public function new() {}
}

private class PrecBand {
	public var x0 = 0;
	public var y0 = 0;
	public var w = 0;
	public var h = 0;
	public var inc:Null<TagTree> = null;
	public var zb:Null<TagTree> = null;

	public function new() {}
}

private class Res {
	public var x0 = 0;
	public var y0 = 0;
	public var x1 = 0;
	public var y1 = 0;
	public var ppx = 0;
	public var ppy = 0;
	public var px0 = 0;
	public var py0 = 0;
	public var npx = 0;
	public var npy = 0;
	public var bands:Array<Band> = [];
	public final prec = new Map<Int, Array<PrecBand>>();
	public var nl:Vector<Int>;

	public function new() {}
}

private class TileComp {
	public var dx = 0;
	public var dy = 0;
	public var prec = 0;
	public var levels = 0;
	public var red = 0;
	public var R = 0;
	public var rev = false;
	public var style = 0;
	public var roi = 0;
	public var res:Array<Res> = [];

	public function new() {}
}

class Jpx {
	static inline var MAX_COMPONENTS = 256;
	static inline var MAX_BLOCKS = 1 << 22;
	static inline var MAX_PRECINCTS = 1 << 20;
	static inline var MAX_PACKETS = 1 << 24;

	static inline function u16(d:Bytes, p:Int):Int
		return p + 1 < d.length && p >= 0 ? (d.get(p) << 8) | d.get(p + 1) : 0;

	static inline function u32(d:Bytes, p:Int):Int
		return p + 3 < d.length && p >= 0 ? (d.get(p) << 24) | (d.get(p + 1) << 16) | (d.get(p + 2) << 8) | d.get(p + 3) : 0;

	static inline function at(d:Bytes, p:Int):Int
		return p < d.length && p >= 0 ? d.get(p) : 0;

	static function bad():Dynamic
		throw "JPX";

	static inline function cdiv(a:Float, b:Float):Int
		return Std.int(Math.ceil(a / b));

	static inline function fdiv(a:Float, b:Float):Int
		return Std.int(Math.floor(a / b));

	static inline function pow2(n:Int):Float
		return Math.pow(2, n);

	static function cat(parts:Array<Bytes>):Bytes {
		if (parts.length == 1) return parts[0];
		var n = 0;
		for (p in parts)
			n += p.length;
		var out = Bytes.alloc(n);
		n = 0;
		for (p in parts) {
			out.blit(n, p, 0, p.length);
			n += p.length;
		}
		return out;
	}

	static function spcod(d:Bytes, q:Int, precincts:Int, c:Cod):Cod {
		var levels = at(d, q), xcb = (at(d, q + 1) & 15) + 2, ycb = (at(d, q + 2) & 15) + 2;
		// (beyond Part 1: HTJ2K's block coder, Part 2's wavelets)
		if (levels > 32 || xcb > 10 || ycb > 10 || xcb + ycb > 12 || at(d, q + 3) & 0x40 != 0 || at(d, q + 4) > 1) bad();
		c.levels = levels;
		c.xcb = xcb;
		c.ycb = ycb;
		c.style = at(d, q + 3);
		c.rev = at(d, q + 4) == 1;
		c.pp = precincts & 1 != 0 && q + 6 + levels <= d.length ? d.sub(q + 5, levels + 1) : null;
		return c;
	}

	static function sqcd(d:Bytes, q:Int, e:Int):Qcd {
		var r = new Qcd();
		r.kind = at(d, q) & 31;
		if (r.kind > 2) bad();
		r.guard = at(d, q) >> 5;
		var i = q + 1;
		while (i < e) {
			r.v.push(r.kind != 0 ? u16(d, i) : (at(d, i) >> 3) << 11);
			i += r.kind != 0 ? 2 : 1;
		}
		return r;
	}

	// marker segments from p to SOT, SOD or end: where it stopped
	public static function segments(d:Bytes, p:Int, end:Int, prm:Params, nc:Int, ppm:Null<Array<{z:Int, b:Bytes}>>):Int {
		var w = nc > 256 ? 2 : 1;
		inline function comp(i:Int)
			return w > 1 ? u16(d, i) : at(d, i);
		while (p + 4 <= end) {
			var m = u16(d, p), q = p + 4, e = p + 2 + u16(d, p + 2);
			if (m == 0xff90 || m == 0xff93 || m < 0xff00 || e < q || e > end) break;
			if (m == 0xff52) {
				var c = new Cod();
				c.sop = at(d, q) & 2 != 0;
				c.eph = at(d, q) & 4 != 0;
				c.order = at(d, q + 1);
				c.layers = u16(d, q + 2);
				c.mct = at(d, q + 4);
				prm.cod = spcod(d, q + 5, at(d, q), c);
			} else if (m == 0xff53) prm.coc.set(comp(q), spcod(d, q + w + 1, at(d, q + w), new Cod()))
			else if (m == 0xff5c) prm.qcd = sqcd(d, q, e)
			else if (m == 0xff5d) prm.qcc.set(comp(q), sqcd(d, q + w, e))
			else if (m == 0xff5e) prm.rgn.set(comp(q), at(d, q + w + 1))
			else if (m == 0xff5f) {
				var i = q;
				while (i + 5 + 2 * w <= e) {
					var ce = comp(i + 4 + w);
					prm.poc.push([at(d, i), comp(i + 1), u16(d, i + 1 + w), at(d, i + 3 + w), ce != 0 ? ce : (w > 1 ? 16384 : 256), at(d, i + 4 + 2 * w)]);
					i += 5 + 2 * w;
				}
			} else if (m == 0xff60) {
				if (ppm != null) ppm.push({z: at(d, q), b: d.sub(q + 1, e - q - 1)});
			} else if (m == 0xff61) prm.ppt.push({z: at(d, q), b: d.sub(q + 1, e - q - 1)});
			p = e;
		}
		return p;
	}

	static function readHeader(d:Bytes, s:Int, end:Int):Header {
		if (u16(d, s) != 0xff4f || u16(d, s + 2) != 0xff51) bad();
		var lsiz = u16(d, s + 4), nc = u16(d, s + 40);
		var siz = new Siz();
		siz.x1 = u32(d, s + 8);
		siz.y1 = u32(d, s + 12);
		siz.x0 = u32(d, s + 16);
		siz.y0 = u32(d, s + 20);
		siz.tw = u32(d, s + 24);
		siz.th = u32(d, s + 28);
		siz.tx0 = u32(d, s + 32);
		siz.ty0 = u32(d, s + 36);
		if (nc == 0 || nc > MAX_COMPONENTS || lsiz < 38 + 3 * nc || s + 4 + lsiz > end) bad();
		var q = s + 42;
		for (_ in 0...nc) {
			var prec = (at(d, q) & 0x7f) + 1;
			if (prec > 30 || at(d, q + 1) == 0 || at(d, q + 2) == 0) bad();
			siz.comps.push(new Comp(prec, at(d, q) > 127, at(d, q + 1), at(d, q + 2)));
			q += 3;
		}
		if (siz.x0 < 0 || siz.y0 < 0 || siz.x1 <= siz.x0 || siz.y1 <= siz.y0 || siz.tw <= 0 || siz.th <= 0 || siz.tx0 < 0 || siz.ty0 < 0 || siz.tx0 > siz.x0
			|| siz.ty0 > siz.y0 || siz.tx0 + siz.tw <= siz.x0 || siz.ty0 + siz.th <= siz.y0) bad();
		siz.ntx = cdiv(siz.x1 - siz.tx0, siz.tw);
		siz.nty = cdiv(siz.y1 - siz.ty0, siz.th);
		if (siz.ntx * 1.0 * siz.nty > 65535) bad();
		var main = new Params(), ppmSegs = [];
		var p = segments(d, s + 4 + lsiz, end, main, nc, ppmSegs);
		var hd = new Header(siz, main);
		if (ppmSegs.length > 0) {
			// (Nppm-prefixed packet headers of each tile-part in turn, split across markers maybe)
			ppmSegs.sort((a, b) -> a.z - b.z);
			var all = cat([for (x in ppmSegs) x.b]);
			hd.ppm = [];
			var i = 0;
			while (i + 4 <= all.length) {
				var n = u32(all, i);
				if (n < 0 || i + 4 + n > all.length) n = all.length - i - 4;
				hd.ppm.push(all.sub(i + 4, n));
				i += 4 + n;
			}
		}
		var i = 0;
		while (p + 12 <= end && u16(d, p) == 0xff90) {
			var psot = u32(d, p + 6), next = psot != 0 ? p + psot : end;
			if (psot != 0 && psot < 14 || psot < 0) break;
			var lim = Std.int(Math.min(next, end));
			var h1 = segments(d, p + 12, lim, new Params(), nc, null);
			if (u16(d, h1) == 0xff93) {
				var d1 = lim - (psot == 0 && u16(d, end - 2) == 0xffd9 ? 2 : 0);
				hd.parts.push({t: u16(d, p + 4), h0: p + 12, h1: h1, d0: h1 + 2, d1: Std.int(Math.max(d1, h1 + 2)), i: i});
			}
			p = next;
			i++;
		}
		return hd;
	}

	// JP2's boxes: the colour space, palette, component mapping, channel definitions, the codestream
	static function readJp2(d:Bytes):{s:Int, e:Int, cs:Null<Int>, pal:Null<{bits:Array<Int>, n:Int, v:Array<Array<Int>>}>, cmap:Null<Array<Array<Int>>>, cdef:Null<Array<Array<Int>>>} {
		var j = {s: -1, e: 0, cs: (null:Null<Int>), pal: null, cmap: null, cdef: null};
		if (u16(d, 0) == 0xff4f) {
			j.s = 0;
			j.e = d.length;
			return j;
		}
		function walk(p:Int, end:Int, depth:Int) {
			while (p + 8 <= end) {
				var len:Float = u32(d, p) >>> 0, hl = 8;
				if (len < 0) len += 4294967296.0;
				var type = u32(d, p + 4);
				if (len == 1) {
					len = (u32(d, p + 8) * 4294967296.0) + (u32(d, p + 12) >>> 0);
					hl = 16;
				} else if (len == 0) len = end - p;
				if (len < hl) break;
				var q = p + hl, e = Std.int(Math.min(p + len, end));
				if (type == 0x6a703268 && depth < 4) walk(q, e, depth + 1) // jp2h
				else if (type == 0x636f6c72) {
					if (j.cs == null) j.cs = at(d, q) == 1 ? u32(d, q + 3) : -1;
				} else if (type == 0x70636c72 && q + 3 <= e) {
					var cols = at(d, q + 2), bits = [], v = [], size = 0;
					for (c in 0...cols) {
						bits.push(at(d, q + 3 + c));
						v.push([]);
						size += ((at(d, q + 3 + c) & 127) >> 3) + 1;
					}
					var n = Std.int(Math.min(Math.min(u16(d, q), 1024), size > 0 ? Math.floor((e - q - 3 - cols) / size) : 0));
					if (n < 0) n = 0;
					var a = q + 3 + cols;
					for (_ in 0...n)
						for (c in 0...cols) {
							var x = 0.0;
							for (_ in 0...((bits[c] & 127) >> 3) + 1)
								x = x * 256 + at(d, a++);
							v[c].push(Std.int(x));
						}
					j.pal = {bits: bits, n: n, v: v};
				} else if (type == 0x636d6170) {
					var cm = [], i = q;
					while (i + 4 <= e) {
						cm.push([u16(d, i), at(d, i + 2), at(d, i + 3)]);
						i += 4;
					}
					j.cmap = cm;
				} else if (type == 0x63646566) {
					var cd = [], n = u16(d, q), i = 0;
					while (i < n && q + 8 + 6 * i <= e) {
						cd.push([u16(d, q + 2 + 6 * i), u16(d, q + 4 + 6 * i), u16(d, q + 6 + 6 * i)]);
						i++;
					}
					j.cdef = cd;
				} else if (type == 0x6a703263 && j.s < 0) { // jp2c
					j.s = q;
					j.e = e;
				}
				p = Std.int(p + len);
			}
		}
		walk(0, d.length, 0);
		if (j.s < 0) {
			// (not a JP2 understood: a codestream anywhere in the data)
			for (i in 0...d.length - 3)
				if (d.get(i) == 0xff && d.get(i + 1) == 0x4f && d.get(i + 2) == 0xff && d.get(i + 3) == 0x51) {
					j.s = i;
					j.e = d.length;
					return j;
				}
			bad();
		}
		return j;
	}

	// ---- the decoder

	public static function decode(data:Bytes, reduce = 0, maxPixels = 1 << 28):Null<JpxImage> {
		try {
			var j = readJp2(data), hd = readHeader(data, j.s, j.e), siz = hd.siz, comps = siz.comps, main = hd.main;
			// (the layout: each output channel's component, and palette column if any)
			var chans = [for (i in 0...comps.length) new Chan(i, null, comps[i].prec)];
			if (j.pal != null && j.cmap != null) {
				var pal = j.pal;
				chans = [
					for (m in j.cmap) {
						var c = m[0], type = m[1], col = m[2];
						if (c >= comps.length) bad();
						if (type != 1 || col >= pal.bits.length) new Chan(c, null, comps[c].prec) else {
							var bits = (pal.bits[col] & 127) + 1, max = pow2(bits) - 1, signed = pal.bits[col] > 127;
							var b = Bytes.alloc(pal.v[col].length);
							for (k in 0...b.length) {
								var x:Float = pal.v[col][k];
								if (signed) x = (x + pow2(bits - 1)) % pow2(bits);
								b.set(k, Math.round(x * 255 / max));
							}
							new Chan(c, b, bits);
						}
					}
				];
			}
			// (cdef: colour channels in association order, then the rest, opacity, in channel order)
			var alpha = -1;
			if (j.cdef != null) {
				var cdef = j.cdef;
				function def(i:Int):Null<Array<Int>> {
					for (x in cdef)
						if (x[0] == i) return x;
					return null;
				}
				function key(i:Int):Float {
					var dd = def(i);
					return dd != null && dd[1] != 0 ? 1073741824.0 + i : ((dd != null && dd[2] != 0 ? dd[2] : 65536) * 256.0 + i);
				}
				var order = [for (i in 0...chans.length) i];
				order.sort((a, b) -> Reflect.compare(key(a), key(b)));
				for (k in 0...order.length) {
					var dd = def(order[k]);
					if (dd != null && (dd[1] == 1 || dd[1] == 2)) {
						alpha = k;
						break;
					}
				}
				chans = [for (i in order) chans[i]];
			}
			var n = chans.length - (alpha < 0 ? 0 : 1), e = j.cs;
			var colorSpace:Null<String> = null, ycc = 0;
			if (e == 16 || e == 20 || e == 21) colorSpace = "rgb" else if (e == 17) colorSpace = "gray" else if (e == 12) colorSpace = "cmyk" else if ((e == 18
				|| e == 1 || e == 3 || e == 4 || e == 24)
				&& n >= 3) {
				colorSpace = "rgb";
				ycc = 1;
			} else if (e == 13 && n >= 4) {
				colorSpace = "cmyk";
				ycc = 2;
			} else if (e == -1) colorSpace = n == 1 ? "gray" : n == 3 ? "rgb" : n == 4 ? "cmyk" : null;
			var levels = 33;
			for (c in 0...comps.length) {
				var cc = main.coc.get(c) ?? main.cod;
				if (cc == null) bad();
				levels = Std.int(Math.min(levels, cc.levels + 1));
			}
			if (reduce < 0) reduce = 0;
			if (reduce > levels - 1) reduce = levels - 1;
			var f = pow2(reduce);
			var ox = cdiv(siz.x0, f), oy = cdiv(siz.y0, f), w = cdiv(siz.x1, f) - ox, h = cdiv(siz.y1, f) - oy;
			var nch = chans.length;
			if (w * 1.0 * h > maxPixels || w * 1.0 * h * nch > 1 << 30 || hd.parts.length == 0) return null;
			var out = Bytes.alloc(w * h * nch);
			var img = new Tiles(data, hd, chans, ycc, reduce, ox, oy, w, h, nch, out);
			var tiles = new Map<Int, Array<Part>>();
			for (p in hd.parts)
				if (p.t < siz.ntx * siz.nty) {
					if (!tiles.exists(p.t)) tiles.set(p.t, []);
					tiles.get(p.t).push(p);
				}
			var done = 0;
			var keys = [for (k in tiles.keys()) k];
			keys.sort((a, b) -> a - b);
			for (t in keys) {
				try {
					img.tile(t, tiles.get(t));
					done++;
				} catch (e:Dynamic) {
					// (a tile not understood stays blank)
				}
			}
			return done > 0 ? {width: w, height: h, components: nch, data: out, colorSpace: colorSpace, alpha: alpha, levels: levels} : null;
		} catch (e:Dynamic) {
			return null;
		}
	}

	// the levels a JPX's codestream has, its size (by its header): reduce chosen by them; null when not one
	public static function info(data:Bytes):Null<{width:Int, height:Int, levels:Int}> {
		try {
			var j = readJp2(data), s = j.s;
			if (u16(data, s) != 0xff4f || u16(data, s + 2) != 0xff51) return null;
			var lsiz = u16(data, s + 4), nc = u16(data, s + 40);
			var main = new Params();
			segments(data, s + 4 + lsiz, j.e, main, nc, null);
			var levels = 33;
			for (c in 0...nc) {
				var cc = main.coc.get(c) ?? main.cod;
				if (cc == null) return null;
				levels = Std.int(Math.min(levels, cc.levels + 1));
			}
			return {width: u32(data, s + 8) - u32(data, s + 16), height: u32(data, s + 12) - u32(data, s + 20), levels: levels};
		} catch (e:Dynamic) {
			return null;
		}
	}

	// ---- tier 2's packets, visited by a progression (B.12.1); emit false: stop

	static function makePrec(res:Res, k:Int, r:Int):Array<PrecBand> {
		var px = res.px0 + (k % res.npx), py = res.py0 + Std.int(k / res.npx);
		var pw = pow2(res.ppx - (r > 0 ? 1 : 0)), ph = pow2(res.ppy - (r > 0 ? 1 : 0));
		return [
			for (b in res.bands) {
				var pb = new PrecBand();
				var xs = Math.max(px * pw, b.x0), xe = Math.min((px + 1) * pw, b.x1), ys = Math.max(py * ph, b.y0), ye = Math.min((py + 1) * ph, b.y1);
				if (xe > xs && ye > ys) {
					pb.x0 = fdiv(xs, pow2(b.xcb));
					pb.y0 = fdiv(ys, pow2(b.ycb));
					pb.w = cdiv(xe, pow2(b.xcb)) - pb.x0;
					pb.h = cdiv(ye, pow2(b.ycb)) - pb.y0;
					pb.inc = new TagTree(pb.w, pb.h);
					pb.zb = new TagTree(pb.w, pb.h);
				}
				pb;
			}
		];
	}

	static function progress(comps:Array<TileComp>, tx0:Int, ty0:Int, poc:Array<Int>, emit:(c:Int, r:Int, k:Int, l:Int) -> Bool):Bool {
		var rs = poc[0], cs = poc[1], le = poc[2], re = poc[3], ce = poc[4], order = poc[5];
		if (order < 2) {
			var n1 = order != 0 ? re : le, n2 = order != 0 ? le : re;
			for (a in (order != 0 ? rs : 0)...n1)
				for (b in (order != 0 ? 0 : rs)...n2)
					for (c in cs...ce) {
						var r = order != 0 ? a : b;
						if (r >= comps[c].res.length) continue;
						var res = comps[c].res[r];
						for (k in 0...res.npx * res.npy)
							if (!emit(c, r, k, order != 0 ? b : a)) return false;
					}
			return true;
		}
		if (order > 4) return false;
		// (sort keys: RPCL by r, y, x, c; PCRL by y, x, c, r; CPRL by c, y, x, r: two exact doubles)
		var k1 = [], k2 = [], id = [];
		for (c in cs...ce) {
			var comp = comps[c];
			var r = rs;
			while (r < re && r < comp.res.length) {
				var res = comp.res[r], sx = comp.dx * pow2(res.ppx + comp.levels - r), sy = comp.dy * pow2(res.ppy + comp.levels - r);
				for (k in 0...res.npx * res.npy) {
					var x = Math.max(tx0, (res.px0 + (k % res.npx)) * sx), y = Math.max(ty0, (res.py0 + Std.int(k / res.npx)) * sy);
					k1.push(order == 2 ? r * 8589934592.0 + y : order == 3 ? y : c * 8589934592.0 + y);
					k2.push(order == 2 ? x * 256 + c : order == 3 ? (x * 256 + c) * 64 + r : x * 64 + r);
					id.push(c);
					id.push(r);
					id.push(k);
				}
				r++;
			}
		}
		var ord = [for (i in 0...k1.length) i];
		ord.sort((a, b) -> k1[a] < k1[b] ? -1 : k1[a] > k1[b] ? 1 : k2[a] < k2[b] ? -1 : k2[a] > k2[b] ? 1 : 0);
		for (i in ord)
			for (l in 0...le)
				if (!emit(id[3 * i], id[3 * i + 1], id[3 * i + 2], l)) return false;
		return true;
	}

	public static function segment(k:Int, style:Int):Int
		return style & T1.TERMALL != 0 ? k : style & T1.BYPASS != 0 && k >= 10 ? 1 + Std.int(((k - 10) * 2) / 3) : 0;

	// (for Tiles)
	public static function tileComps(siz:Siz, main:Params, tp:Params, cod:Cod, reduce:Int, tx0:Int, ty0:Int, tx1:Int, ty1:Int):Array<TileComp> {
		var blocks = 0.0, precincts = 0.0;
		return [
			for (c in 0...siz.comps.length) {
				var sc = siz.comps[c];
				var cc = tp.coc.get(c) ?? tp.cod ?? main.coc.get(c) ?? cod;
				var qc = tp.qcc.get(c) ?? tp.qcd ?? main.qcc.get(c) ?? main.qcd;
				if (qc == null) bad();
				var roi = Std.int(Math.min(tp.rgn.get(c) ?? main.rgn.get(c) ?? 0, 30)), L = cc.levels, red = Std.int(Math.min(reduce, L));
				var tcx0 = cdiv(tx0, sc.dx), tcx1 = cdiv(tx1, sc.dx), tcy0 = cdiv(ty0, sc.dy), tcy1 = cdiv(ty1, sc.dy);
				var res:Array<Res> = [];
				for (r in 0...L + 1) {
					var s = pow2(L - r), x0 = cdiv(tcx0, s), x1 = cdiv(tcx1, s), y0 = cdiv(tcy0, s), y1 = cdiv(tcy1, s);
					var pp = cc.pp != null && r < cc.pp.length ? cc.pp.get(r) : 0xff, lift = r > 0 ? 1 : 0;
					var ppx = Std.int(Math.max(pp & 15, lift)), ppy = Std.int(Math.max(pp >> 4, lift));
					var R = new Res();
					R.x0 = x0;
					R.y0 = y0;
					R.x1 = x1;
					R.y1 = y1;
					R.ppx = ppx;
					R.ppy = ppy;
					R.px0 = fdiv(x0, pow2(ppx));
					R.py0 = fdiv(y0, pow2(ppy));
					R.npx = x1 > x0 ? cdiv(x1, pow2(ppx)) - R.px0 : 0;
					R.npy = y1 > y0 ? cdiv(y1, pow2(ppy)) - R.py0 : 0;
					var xcb = Std.int(Math.min(cc.xcb, ppx - lift)), ycb = Std.int(Math.min(cc.ycb, ppy - lift)), lo = r > 0 ? res[r - 1] : null;
					if ((precincts += R.npx * 1.0 * R.npy) > MAX_PRECINCTS) bad();
					R.bands = [
						for (b in (r > 0 ? [1, 2, 3] : [0])) {
							var xo = b & 1, yo = b >> 1, sb = pow2(r > 0 ? L - r + 1 : L);
							var bx0 = cdiv(tcx0 - (xo * sb) / 2, sb), bx1 = cdiv(tcx1 - (xo * sb) / 2, sb);
							var by0 = cdiv(tcy0 - (yo * sb) / 2, sb), by1 = cdiv(tcy1 - (yo * sb) / 2, sb);
							var gx = fdiv(bx0, pow2(xcb)), gy = fdiv(by0, pow2(ycb));
							var nbx = bx1 > bx0 ? cdiv(bx1, pow2(xcb)) - gx : 0, nby = by1 > by0 ? cdiv(by1, pow2(ycb)) - gy : 0;
							if ((blocks += nbx * 1.0 * nby) > MAX_BLOCKS) bad();
							// (subband b's quantization; the derived style scales the LL's step, E.1.1.1)
							var i = r > 0 ? 3 * r - 3 + b : 0;
							var q = qc.kind == 1 ? qc.v[0] - ((r > 0 ? r - 1 : 0) << 11) : (i < qc.v.length ? qc.v[i] : qc.v.length > 0 ? qc.v[qc.v.length - 1] : 0);
							var eps = q >> 11, gain = b == 3 ? 2 : b != 0 ? 1 : 0;
							var B = new Band();
							B.x0 = bx0;
							B.y0 = by0;
							B.x1 = bx1;
							B.y1 = by1;
							B.o = b == 1 ? 1 : b == 3 ? 2 : 0;
							B.ox = xo != 0 ? lo.x1 - lo.x0 : 0;
							B.oy = yo != 0 ? lo.y1 - lo.y0 : 0;
							B.xcb = xcb;
							B.ycb = ycb;
							B.bx0 = gx;
							B.by0 = gy;
							B.nbx = nbx;
							B.nby = nby;
							B.blocks = new Vector(nbx * nby);
							B.mb = qc.guard + eps - 1 + roi;
							B.step = cc.rev ? 0 : (pow2(sc.prec + gain - eps) * (1 + (q & 2047) / 2048)) / 2;
							B;
						}
					];
					R.nl = new Vector<Int>(R.npx * R.npy, 0);
					res.push(R);
				}
				var t = new TileComp();
				t.dx = sc.dx;
				t.dy = sc.dy;
				t.prec = sc.prec;
				t.levels = L;
				t.red = red;
				t.R = L - red;
				t.rev = cc.rev;
				t.style = cc.style;
				t.roi = roi;
				t.res = res;
				t;
			}
		];
	}

	public static function packets(d:Bytes, hd:Header, tp:Params, parts:Array<Part>, comps:Array<TileComp>, cod:Cod, tx0:Int, ty0:Int):Bytes {
		var nc = comps.length;
		var body = cat([for (p in parts) d.sub(p.d0, Std.int(Math.max(0, Math.min(p.d1, d.length) - p.d0)))]);
		var ppm = hd.ppm;
		var hdr:Null<Bytes> = ppm != null ? cat([for (p in parts) p.i < ppm.length ? ppm[p.i] : Bytes.alloc(0)]) : tp.ppt.length > 0 ? {
			tp.ppt.sort((a, b) -> a.z - b.z);
			cat([for (x in tp.ppt) x.b]);
		} : null;
		var bits = new Bits(hdr ?? body);
		var pBlk:Array<Blk> = [], pLen:Array<Int> = [], pSeg:Array<Int> = [];
		var bp = 0, visits = 0;
		function emit(c:Int, r:Int, k:Int, l:Int):Bool {
			var comp = comps[c], res = comp.res[r];
			if (++visits > MAX_PACKETS) return false;
			if (res.nl[k] != l) return true;
			res.nl[k]++;
			if (hdr != null ? bits.p >= bits.e : bp >= body.length) return false;
			if (cod.sop && at(body, bp) == 0xff && at(body, bp + 1) == 0x91) bp += 6;
			if (hdr == null) bits.p = bp;
			var np = 0;
			if (bits.bit() != 0) {
				var prec = res.prec.get(k);
				if (prec == null) {
					prec = makePrec(res, k, r);
					res.prec.set(k, prec);
				}
				for (b in 0...prec.length) {
					var pb = prec[b], band = res.bands[b];
					for (i in 0...pb.w * pb.h) {
						var bi = (pb.y0 + Std.int(i / pb.w) - band.by0) * band.nbx + pb.x0 + (i % pb.w) - band.bx0;
						if (bi < 0 || bi >= band.blocks.length) return false;
						var blk = band.blocks[bi];
						if (blk == null) {
							// (first inclusion: the inclusion tag tree says in which layer, then the zero bit-planes)
							if (pb.inc.decode(bits, i, l + 1) == 0) continue;
							pb.zb.decode(bits, i, 99);
							blk = band.blocks[bi] = new Blk(pb.zb.v[i]);
						} else if (bits.bit() == 0) continue;
						// (the new coding passes, Table B.4)
						var n = 1 + bits.bit();
						if (n > 1 && (n += bits.bit()) > 2 && (n += bits.bits(2)) == 6 && (n += bits.bits(5)) == 37) n += bits.bits(7);
						while (bits.bit() != 0)
							if (++blk.lb > 32) return false;
						// (a length each codeword segment the new passes touch)
						var kk = blk.n, e = kk + n;
						while (kk < e) {
							var s = segment(kk, comp.style), m = 0;
							do
								m++
							while (++kk < e && segment(kk, comp.style) == s);
							var lg = 0;
							while ((m >> (lg + 1)) != 0)
								lg++;
							pBlk[np] = blk;
							pSeg[np] = s;
							pLen[np++] = bits.bits(blk.lb + lg);
						}
						blk.n += n;
					}
				}
			}
			bits.align();
			if (cod.eph && at(bits.d, bits.p) == 0xff && at(bits.d, bits.p + 1) == 0x92) bits.p += 2;
			if (bits.p > bits.e) return false;
			if (hdr == null) bp = bits.p;
			for (i in 0...np) {
				var len = Std.int(Math.max(0, Math.min(pLen[i], body.length - bp)));
				if (r <= comp.R) {
					pBlk[i].ch.push(bp);
					pBlk[i].ch.push(len);
					pBlk[i].ch.push(pSeg[i]);
				}
				bp += len;
			}
			return true;
		}
		try {
			var top = 0;
			for (c in comps)
				top = Std.int(Math.max(top, c.levels));
			top++;
			var src = tp.poc.length > 0 ? tp.poc : hd.main.poc;
			var pocs = [
				for (p in src)
					[p[0], p[1], Std.int(Math.min(p[2], cod.layers)), Std.int(Math.min(p[3], top)), Std.int(Math.min(p[4], nc)), p[5]]
			];
			if (pocs.length == 0) pocs = [[0, 0, cod.layers, top, nc, cod.order]];
			for (poc in pocs)
				if (!progress(comps, tx0, ty0, poc, emit)) break;
		} catch (e:Dynamic) {
			// (damaged packet headers: what arrived before)
		}
		return body;
	}
}

// the tiles into the output: tier 1, dequantization, the inverse wavelet transform, the component transform
private class Tiles {
	final d:Bytes;
	final hd:Header;
	final chans:Array<Chan>;
	final ycc:Int;
	final reduce:Int;
	final ox:Int;
	final oy:Int;
	final w:Int;
	final h:Int;
	final nch:Int;
	final out:Bytes;
	final t1 = new T1();
	final bufs:Array<Vector<Float>> = [];

	public function new(d, hd, chans, ycc, reduce, ox, oy, w, h, nch, out) {
		this.d = d;
		this.hd = hd;
		this.chans = chans;
		this.ycc = ycc;
		this.reduce = reduce;
		this.ox = ox;
		this.oy = oy;
		this.w = w;
		this.h = h;
		this.nch = nch;
		this.out = out;
	}

	public function tile(t:Int, parts:Array<Part>) {
		var siz = hd.siz, main = hd.main, nc = siz.comps.length;
		var tx = t % siz.ntx, ty = Std.int(t / siz.ntx);
		var tx0 = Std.int(Math.max(siz.tx0 + tx * siz.tw, siz.x0)), tx1 = Std.int(Math.min(siz.tx0 + (tx + 1) * siz.tw, siz.x1));
		var ty0 = Std.int(Math.max(siz.ty0 + ty * siz.th, siz.y0)), ty1 = Std.int(Math.min(siz.ty0 + (ty + 1) * siz.th, siz.y1));
		var tp = new Params();
		for (p in parts)
			Jpx.segments(d, p.h0, p.h1, tp, nc, null);
		var cod = tp.cod ?? main.cod;
		if (cod == null) throw "JPX";
		var comps = Jpx.tileComps(siz, main, tp, cod, reduce, tx0, ty0, tx1, ty1);
		var body = Jpx.packets(d, hd, tp, parts, comps, cod, tx0, ty0);
		var bufs = [
			for (c in 0...comps.length) {
				var comp = comps[c], top = comp.res[comp.R], W = top.x1 - top.x0, n = W * (top.y1 - top.y0);
				var buf = this.bufs[c];
				if (buf == null || buf.length < n) {
					buf = new Vector<Float>(n, 0.0);
					this.bufs[c] = buf;
				} else
					for (i in 0...n)
						buf[i] = 0;
				for (r in 0...comp.R + 1)
					for (band in comp.res[r].bands) {
						var blocks = band.blocks, xcb = band.xcb, ycb = band.ycb;
						for (i in 0...blocks.length) {
							var blk = blocks[i];
							if (blk == null || blk.ch.length == 0) continue;
							var bx = band.bx0 + (i % band.nbx), by = band.by0 + Std.int(i / band.nbx);
							var x0 = Std.int(Math.max(bx << xcb, band.x0)), x1 = Std.int(Math.min((bx + 1) << xcb, band.x1));
							var y0 = Std.int(Math.max(by << ycb, band.y0)), y1 = Std.int(Math.min((by + 1) << ycb, band.y1));
							var planes = Std.int(Math.min(band.mb - blk.z, 29)), bw = x1 - x0, bh = y1 - y0;
							if (planes < 1 || bw < 1 || bh < 1) continue;
							var v = t1.decode(body, blk.ch, blk.n, bw, bh, band.o, comp.style, planes);
							place(buf, (band.oy + y0 - band.y0) * W + band.ox + x0 - band.x0, W, v, bw, bh, band.step, comp.roi);
						}
					}
				Dwt.idwt(buf, W, comp.res.slice(0, comp.R + 1), comp.rev);
				buf;
			}
		];
		// (the multiple component transform, Annex G, on the first three components when they match)
		inline function same(c:TileComp)
			return c.dx == comps[0].dx && c.dy == comps[0].dy && c.red == comps[0].red;
		if (cod.mct == 1 && nc >= 3 && same(comps[1]) && same(comps[2])) {
			var a0 = bufs[0], a1 = bufs[1], a2 = bufs[2];
			var top = comps[0].res[comps[0].R], n = (top.x1 - top.x0) * (top.y1 - top.y0);
			if (comps[0].rev) {
				for (i in 0...n) {
					var y = a0[i], u = a1[i], v = a2[i], g = y - (Std.int(u + v) >> 2);
					a0[i] = v + g;
					a1[i] = g;
					a2[i] = u + g;
				}
			} else
				for (i in 0...n) {
					var y = a0[i], u = a1[i], v = a2[i];
					a0[i] = y + 1.402 * v;
					a1[i] = y - 0.34413 * u - 0.71414 * v;
					a2[i] = y + 1.772 * u;
				}
		}
		write(comps, bufs, tx0, ty0, tx1, ty1);
	}

	// a decoded block dequantized into the coefficients at o (step: half the quantization step; 0 reversible)
	static function place(buf:Vector<Float>, o:Int, W:Int, v:Vector<Int>, w:Int, h:Int, step:Float, roi:Int) {
		if (roi > 0) {
			// (max-shift ROI: coefficients above the background's range scaled up, Annex H)
			var thr = 1 << (roi + 1);
			for (j in 0...w * h) {
				var q = v[j];
				if ((q < 0 ? -q : q) >= thr) v[j] = q < 0 ? -(-q >> roi) : q >> roi;
			}
		}
		var j = 0;
		for (_ in 0...h) {
			if (step != 0) for (_ in 0...w) buf[o++] = v[j++] * step; else for (_ in 0...w) {
				buf[o++] = (v[j] + (v[j] >>> 31)) >> 1;
				j++;
			}
			o += W - w;
		}
	}

	static inline function clamp(v:Float):Int
		return v <= 0 ? 0 : v >= 255 ? 255 : Std.int(v + 0.5);

	// level-shifted, scaled to 8 bits, interleaved into the output
	function write(comps:Array<TileComp>, bufs:Array<Vector<Float>>, tx0:Int, ty0:Int, tx1:Int, ty1:Int) {
		var f = Math.pow(2, reduce);
		var X0 = Std.int(Math.ceil(tx0 / f)), X1 = Std.int(Math.ceil(tx1 / f)), Y0 = Std.int(Math.ceil(ty0 / f)), Y1 = Std.int(Math.ceil(ty1 / f)), tw = X1 - X0;
		if (tw < 1 || Y1 <= Y0) return;
		var maps = [], Ws = [], Hs = [], y0s = [], sys = [], shifts = [], scales = [];
		for (ch in chans) {
			var comp = comps[ch.c], top = comp.res[comp.R], W = top.x1 - top.x0, H = top.y1 - top.y0, s = Math.pow(2, reduce - comp.red);
			var map = new Vector<Int>(tw, 0);
			for (x in 0...tw)
				map[x] = Std.int(Math.min(Math.max(Math.floor(((X0 + x) * s) / comp.dx) - top.x0, 0), W - 1));
			maps.push(map);
			Ws.push(W);
			Hs.push(H);
			y0s.push(top.y0);
			sys.push(s / comp.dy);
			shifts.push(Math.pow(2, comp.prec - 1));
			scales.push(255 / (Math.pow(2, comp.prec) - 1));
		}
		for (y in Y0...Y1) {
			var o0 = ((y - oy) * w + X0 - ox) * nch;
			if (y - oy < 0 || y - oy >= h) continue;
			for (ch in 0...nch) {
				var a = bufs[chans[ch].c], pal = chans[ch].pal, map = maps[ch], W = Ws[ch], H = Hs[ch];
				if (W <= 0 || H <= 0) continue;
				var row = Std.int(Math.min(Math.max(Math.floor(y * sys[ch]) - y0s[ch], 0), H - 1)) * W, shift = shifts[ch], scale = scales[ch];
				var o = o0 + ch;
				for (x in 0...tw) {
					if (X0 + x - ox >= 0 && X0 + x - ox < w) {
						var v = a[row + map[x]] + shift;
						if (pal != null) {
							var p = Math.round(v);
							out.set(o, pal.get(p < 0 ? 0 : p >= pal.length ? pal.length - 1 : p));
						} else
							out.set(o, scale == 1 ? clamp(v) : clamp(Math.round(v) * scale));
					}
					o += nch;
				}
			}
			if (ycc != 0) {
				// (sYCC to RGB; YCCK to CMY, inverted RGB, and K)
				var inv = ycc == 2 ? 255 : 0, sign = inv != 0 ? -1 : 1;
				var o = o0;
				for (_ in 0...tw) {
					var Y = out.get(o), cb = out.get(o + 1) - 128, cr = out.get(o + 2) - 128;
					out.set(o, clamp(inv + sign * (Y + 1.402 * cr)));
					out.set(o + 1, clamp(inv + sign * (Y - 0.344136 * cb - 0.714136 * cr)));
					out.set(o + 2, clamp(inv + sign * (Y + 1.772 * cb)));
					o += nch;
				}
			}
		}
	}
}

// the inverse wavelet transform (Annex F): the reversible 5/3 and the irreversible 9/7, by lifting
private class Dwt {
	static inline var PAD = 4;
	static final LIFT = [0.443506852043971, 0.882911075530934, -0.052980118572961, -1.586134342059924];
	static inline var DELTA = 0.443506852043971;
	static inline var GAMMA = 0.882911075530934;
	static inline var BETA = -0.052980118572961;
	static inline var ALPHA = -1.586134342059924;
	static inline var K = 1.230174104914001;

	static var line = new Vector<Float>(0);
	static var at = new Vector<Int>(0);
	static var seen = new Vector<Bool>(0);
	static var spare = new Vector<Float>(0);

	static inline function sh(v:Float, n:Int):Int
		return Std.int(v) >> n;

	// (j's index in a line of n samples, mirrored)
	static function mirror(j:Int, n:Int):Int {
		var p = 2 * (n - 1);
		if (p == 0) return 0;
		j %= p;
		if (j < 0) j += p;
		return j < n ? j : p - j;
	}

	public static function idwt(a:Vector<Float>, stride:Int, levels:Array<Res>, rev:Bool) {
		var max = 0;
		for (l in levels)
			max = Std.int(Math.max(max, Math.max(l.x1 - l.x0, l.y1 - l.y0)));
		if (line.length < max + 2 * PAD) {
			line = new Vector<Float>(max + 2 * PAD, 0.0);
			at = new Vector<Int>(max + 2, 0);
			seen = new Vector<Bool>(max, false);
		}
		for (r in 1...levels.length) {
			var l = levels[r], lo = levels[r - 1], w = l.x1 - l.x0, h = l.y1 - l.y0;
			if (w <= 0 || h <= 0) continue;
			// (rows, then columns; the rows also apply the columns' 9/7 scaling)
			var lh = lo.y1 - lo.y0, kl = rev || h < 2 ? 1 : K, kh = rev || h < 2 ? 1 : 1 / K;
			for (y in 0...h)
				row(a, y * stride, w, lo.x1 - lo.x0, l.x0 & 1, rev, y < lh ? kl : kh);
			columns(a, stride, w, h, lh, l.y0 & 1, rev);
		}
	}

	static function row(a:Vector<Float>, off:Int, n:Int, nl:Int, odd:Int, rev:Bool, k:Float) {
		var t = line, P = PAD;
		if (n == 1) {
			// (a lone low-pass sample is the value; a lone high-pass one twice it, F.3.7)
			if (odd != 0) a[off] = rev ? sh(a[off], 1) : a[off] / 2;
			a[off] *= k;
			return;
		}
		var kl = rev ? 1 : K, kh = rev ? 1 : 1 / K;
		var j = P + odd;
		for (q in 0...nl) {
			t[j] = a[off + q] * kl;
			j += 2;
		}
		j = P + 1 - odd;
		for (q in nl...n) {
			t[j] = a[off + q] * kh;
			j += 2;
		}
		for (i in 1...P + 1) {
			t[P - i] = t[P + mirror(-i, n)];
			t[P + n - 1 + i] = t[P + mirror(n - 1 + i, n)];
		}
		var o = off - P, e = P + n;
		var h1 = t[1 - odd], d2 = 0.0;
		if (rev) {
			var j = 2 - odd;
			while (j <= e) {
				var hh = t[j + 1], d:Float = t[j] - sh(h1 + hh + 2, 2), g:Float = h1 + sh(d2 + d, 1);
				if (j >= P && j < e) a[o + j] = d;
				if (j > P && j <= e) a[o + j - 1] = g;
				h1 = hh;
				d2 = d;
				j += 2;
			}
			return;
		}
		var g3 = 0.0, b4 = 0.0;
		var j = 2 - odd;
		while (j < e + 3) {
			var hh = j + 1 < t.length ? t[j + 1] : 0.0, d = t[j] - DELTA * (h1 + hh), g = h1 - GAMMA * (d2 + d), b = d2 - BETA * (g3 + g);
			if (j - 2 >= P && j - 2 < e) a[o + j - 2] = b * k;
			if (j - 3 >= P && j - 3 < e) a[o + j - 3] = (g3 - ALPHA * (b4 + b)) * k;
			h1 = hh;
			d2 = d;
			g3 = g;
			b4 = b;
			j += 2;
		}
	}

	static function columns(a:Vector<Float>, stride:Int, w:Int, n:Int, nl:Int, odd:Int, rev:Bool) {
		if (n == 1) {
			if (odd != 0) for (x in 0...w) a[x] = rev ? sh(a[x], 1) : a[x] / 2;
			return;
		}
		// (the row holding sample j of the interleaved column, low-pass rows first, j = -1..n mirrored)
		for (jj in -1...n + 1) {
			var k = mirror(jj, n);
			at[jj + 1] = (((k ^ odd) & 1) != 0 ? nl + ((k - 1 + odd) >> 1) : (k - odd) >> 1) * stride;
		}
		var steps = rev ? 2 : 4, rows = at;
		var i = 1 - odd;
		while (i < n + steps) {
			if (i > steps && i < n) {
				var r0 = rows[i + 1], r1 = rows[i], r2 = rows[i - 1], r3 = rows[i - 2];
				if (rev) {
					for (x in 0...w) {
						var n1:Float = a[r1 + x] - sh(a[r2 + x] + a[r0 + x] + 2, 2);
						a[r1 + x] = n1;
						a[r2 + x] += sh(a[r3 + x] + n1, 1);
					}
				} else {
					var r4 = rows[i - 3], r5 = rows[i - 4];
					for (x in 0...w) {
						var p3 = a[r3 + x], p4 = a[r4 + x];
						var n1 = a[r1 + x] - DELTA * (a[r2 + x] + a[r0 + x]);
						var n2 = a[r2 + x] - GAMMA * (p3 + n1);
						var n3 = p3 - BETA * (p4 + n2);
						a[r1 + x] = n1;
						a[r2 + x] = n2;
						a[r3 + x] = n3;
						a[r4 + x] = p4 - ALPHA * (a[r5 + x] + n3);
					}
				}
				i += 2;
				continue;
			}
			for (s in 0...steps) {
				var r = i - 1 - s;
				if (r < 0 || r >= n) continue;
				var dd = rows[r + 1], u = rows[r], v = rows[r + 2], c = LIFT[s];
				if (!rev) for (x in 0...w) a[dd + x] -= c * (a[u + x] + a[v + x]) else if (s != 0) for (x in 0...w) a[dd + x] += sh(a[u + x] + a[v + x], 1) else
					for (x in 0...w)
						a[dd + x] -= sh(a[u + x] + a[v + x] + 2, 2);
			}
			i += 2;
		}
		// (the rows put in order, by the permutation's cycles, with one spare row)
		for (jj in 0...n)
			seen[jj] = false;
		if (spare.length < w) spare = new Vector<Float>(w, 0.0);
		var t = spare;
		for (jj in 0...n) {
			if (seen[jj]) continue;
			for (x in 0...w)
				t[x] = a[jj * stride + x];
			var k = jj;
			while (true) {
				seen[k] = true;
				var s = at[k + 1];
				if (s == jj * stride) {
					for (x in 0...w)
						a[k * stride + x] = t[x];
					break;
				}
				for (x in 0...w)
					a[k * stride + x] = a[s + x];
				k = Std.int(s / stride);
			}
		}
	}
}

// tier 1 (Annexes C and D): the MQ decoder and the significance propagation, magnitude refinement and
// cleanup passes rebuilding a code-block's coefficients a bit-plane at a time
private class T1 {
	public static inline var BYPASS = 1;
	static inline var RESET = 2;
	public static inline var TERMALL = 4;
	static inline var VCAUSAL = 8;
	static inline var SEGSYM = 32;

	static final QEV = [
		0x5601, 0x3401, 0x1801, 0x0ac1, 0x0521, 0x0221, 0x5601, 0x5401, 0x4801, 0x3801, 0x3001, 0x2401, 0x1c01, 0x1601, 0x5601, 0x5401, 0x5101, 0x4801, 0x3801,
		0x3401, 0x3001, 0x2801, 0x2401, 0x2201, 0x1c01, 0x1801, 0x1601, 0x1401, 0x1201, 0x1101, 0x0ac1, 0x09c1, 0x08a1, 0x0521, 0x0441, 0x02a1, 0x0221, 0x0141,
		0x0111, 0x0085, 0x0049, 0x0025, 0x0015, 0x0009, 0x0005, 0x0001, 0x5601];
	static final NLPS = [
		1, 6, 9, 12, 29, 33, 6, 14, 14, 14, 17, 18, 20, 21, 14, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
		37, 38, 39, 40, 41, 42, 43, 46];

	static inline var N = 1;
	static inline var S = 2;
	static inline var W = 4;
	static inline var E = 8;
	static inline var NW = 16;
	static inline var NE = 32;
	static inline var SW = 64;
	static inline var SE = 128;
	static inline var NB = 255;
	static inline var SIG = 0x1000;
	static inline var VISIT = 0x2000;
	static inline var REF = 0x4000;
	static inline var CAUSAL = 0xffff & ~(2 | 64 | 128 | (2 << 8));

	static var QE:Vector<Int>;
	static var NM:Vector<Int>;
	static var NL:Vector<Int>;
	static var ZC:Vector<Int>;
	static var SC:Vector<Int>;

	static function tables() {
		if (QE != null) return;
		QE = new Vector(94, 0);
		NM = new Vector(94, 0);
		NL = new Vector(94, 0);
		for (s in 0...94) {
			var i = s >> 1, m = s & 1;
			QE[s] = QEV[i];
			NM[s] = ((i == 5 ? 38 : i == 13 ? 29 : i > 44 ? i : i + 1) << 1) | m;
			NL[s] = (NLPS[i] << 1) | (i == 0 || i == 6 || i == 14 ? m ^ 1 : m);
		}
		ZC = new Vector(768, 0);
		for (f in 0...256) {
			var h = ((f >> 2) & 1) + ((f >> 3) & 1), v = (f & 1) + ((f >> 1) & 1);
			var d = ((f >> 4) & 1) + ((f >> 5) & 1) + ((f >> 6) & 1) + ((f >> 7) & 1);
			for (o in 0...2) {
				// (HL swaps the horizontal and vertical neighbours' roles)
				var a = o != 0 ? v : h, b = o != 0 ? h : v;
				ZC[(o << 8) | f] = a == 2 ? 8 : a != 0 ? (b != 0 ? 7 : d != 0 ? 6 : 5) : b != 0 ? b + 2 : d > 1 ? 2 : d;
			}
			var hv = h + v;
			ZC[512 | f] = d > 2 ? 8 : d == 2 ? (hv != 0 ? 7 : 6) : d != 0 ? (hv > 1 ? 5 : hv + 3) : hv > 1 ? 2 : hv;
		}
		SC = new Vector(256, 0);
		inline function sgn(f:Int, bit:Int):Int
			return f & bit != 0 ? (f & (bit << 4) != 0 ? -1 : 1) : 0;
		inline function sign(x:Int):Int
			return x > 0 ? 1 : x < 0 ? -1 : 0;
		for (f in 0...256) {
			var v = sign(sgn(f, N) + sgn(f, S)), h = sign(sgn(f, W) + sgn(f, E)), x = 0;
			if (h < 0 || (h == 0 && v < 0)) {
				h = -h;
				v = -v;
				x = 32;
			}
			SC[f] = (h != 0 ? 12 + v : 9 + v) | x;
		}
	}

	var d = Bytes.alloc(8192);
	var p = 0;
	var a = 0;
	var c = 0;
	var ct = 0;
	final cx = new Vector<Int>(19, 0);
	var fl = new Vector<Int>(6156, 0);
	public var out = new Vector<Int>(4096, 0);
	var w = 0;
	var h = 0;
	var sw = 0;
	var zo = 0;
	var vm = 0;

	public function new()
		tables();

	inline function db(i:Int):Int
		return i < d.length ? d.get(i) : 0xff;

	// a w x h block (at most 4096 samples) from chunks (offset, length, segment each) of src
	public function decode(src:Bytes, chunks:Array<Int>, passes:Int, w:Int, h:Int, orient:Int, style:Int, planes:Int):Vector<Int> {
		var sw = w + 2;
		if (out.length < w * h) out = new Vector<Int>(w * h, 0);
		if (fl.length < sw * (h + 2)) fl = new Vector<Int>(sw * (h + 2), 0);
		var o = out;
		for (i in 0...w * h)
			o[i] = 0;
		for (i in 0...sw * (h + 2))
			fl[i] = 0;
		this.w = w;
		this.h = h;
		this.sw = sw;
		zo = orient << 8;
		vm = style & VCAUSAL != 0 ? CAUSAL : 0xffff;
		reset();
		passes = Std.int(Math.min(passes, 3 * planes - 2));
		var k = 0, ci = 0;
		while (k < passes) {
			var seg = Jpx.segment(k, style), n = 0;
			while (ci < chunks.length && chunks[ci + 2] <= seg) {
				if (chunks[ci + 2] == seg) {
					var off = chunks[ci], len = Std.int(Math.max(0, Math.min(chunks[ci + 1], src.length - off)));
					if (d.length < n + len + 2) {
						var nd = Bytes.alloc((n + len) * 2 + 2);
						nd.blit(0, d, 0, n);
						d = nd;
					}
					d.blit(n, src, off, len);
					n += len;
				}
				ci += 3;
			}
			d.set(n, 0xff);
			d.set(n + 1, 0xff);
			var raw = style & BYPASS != 0 && k >= 10 && k % 3 != 0;
			p = c = ct = 0;
			if (!raw) {
				// (INITDEC, C.3.5)
				c = db(0) << 16;
				byteIn();
				c <<= 7;
				ct -= 7;
				a = 0x8000;
			}
			do {
				var bp = planes - 1 - Std.int((k + 2) / 3), t = k % 3;
				if (t == 0) {
					cleanup(bp);
					if (style & SEGSYM != 0) for (_ in 0...4) mq(18);
				} else if (t == 1) sigProp(bp, raw) else refine(bp, raw);
				if (style & RESET != 0) reset();
			} while (++k < passes && Jpx.segment(k, style) == seg);
		}
		return o;
	}

	function reset() {
		for (i in 0...19)
			cx[i] = 0;
		cx[0] = 8;
		cx[17] = 6;
		cx[18] = 92;
	}

	function byteIn() {
		if (db(p) != 0xff) {
			p++;
			c = c + (db(p) << 8);
			ct = 8;
		} else if (db(p + 1) > 0x8f) {
			c = c + 0xff00;
			ct = 8;
		} else {
			p++;
			c = c + (db(p) << 9);
			ct = 7;
		}
	}

	// DECODE (C.3.2) in context i; c an int32 holding the unsigned register
	function mq(i:Int):Int {
		var s = cx[i], qe = QE[s];
		var a = this.a - qe, d = s & 1;
		if ((c >>> 16) < qe) {
			if (a < qe) cx[i] = NM[s] else {
				d ^= 1;
				cx[i] = NL[s];
			}
			a = qe;
		} else {
			c = c - (qe << 16);
			if (a & 0x8000 != 0) {
				this.a = a;
				return d;
			}
			if (a < qe) {
				d ^= 1;
				cx[i] = NL[s];
			} else
				cx[i] = NM[s];
		}
		do {
			if (ct == 0) byteIn();
			a <<= 1;
			c <<= 1;
			ct--;
		} while (a & 0x8000 == 0);
		this.a = a;
		return d;
	}

	// a bit of a raw (bypass) segment, the bit stuffed after 0xFF skipped
	function rawBit():Int {
		if (ct == 0) {
			var b = db(p);
			if (c != 0xff) {
				c = b;
				p++;
				ct = 8;
			} else if (b <= 0x8f) {
				c = b;
				p++;
				ct = 7;
			} else
				ct = 8;
		}
		return (c >> --ct) & 1;
	}

	inline function signOf(f:Int):Int {
		var t = SC[(f & 15) | ((f >> 4) & 0xf0)];
		return mq(t & 31) ^ (t >> 5);
	}

	function set(i:Int, neg:Int) {
		fl[i] |= SIG;
		fl[i - sw] |= S | (neg << 9);
		fl[i + sw] |= N | (neg << 8);
		fl[i - 1] |= E | (neg << 11);
		fl[i + 1] |= W | (neg << 10);
		fl[i - sw - 1] |= SE;
		fl[i - sw + 1] |= SW;
		fl[i + sw - 1] |= NE;
		fl[i + sw + 1] |= NW;
	}

	function sigProp(bp:Int, raw:Bool) {
		var one = 3 << bp, y = 0;
		while (y < h) {
			var rows = h - y < 4 ? h - y : 4, i0 = (y + 1) * sw + 1, j0 = y * w;
			for (x in 0...w) {
				if (rows == 4 && (fl[i0 + x] | fl[i0 + x + sw] | fl[i0 + x + 2 * sw] | fl[i0 + x + 3 * sw]) & NB == 0) continue;
				var i = i0 + x, j = j0 + x;
				for (r in 0...rows) {
					var f = fl[i] & (r < 3 ? 0xffff : vm);
					if (f & SIG == 0 && f & NB != 0) {
						if ((raw ? rawBit() : mq(ZC[zo | (f & NB)])) != 0) {
							var neg = raw ? rawBit() : signOf(f);
							out[j] = neg != 0 ? -one : one;
							set(i, neg);
						}
						fl[i] |= VISIT;
					}
					i += sw;
					j += w;
				}
			}
			y += 4;
		}
	}

	function refine(bp:Int, raw:Bool) {
		var half = 1 << bp, y = 0;
		while (y < h) {
			var rows = h - y < 4 ? h - y : 4, i0 = (y + 1) * sw + 1, j0 = y * w;
			for (x in 0...w) {
				if (rows == 4 && (fl[i0 + x] | fl[i0 + x + sw] | fl[i0 + x + 2 * sw] | fl[i0 + x + 3 * sw]) & SIG == 0) continue;
				var i = i0 + x, j = j0 + x;
				for (r in 0...rows) {
					var f = fl[i] & (r < 3 ? 0xffff : vm);
					if (f & (SIG | VISIT) == SIG) {
						var v = out[j];
						out[j] = ((raw ? rawBit() : mq(f & REF != 0 ? 16 : f & NB != 0 ? 15 : 14)) ^ (v >>> 31)) != 0 ? v + half : v - half;
						fl[i] |= REF;
					}
					i += sw;
					j += w;
				}
			}
			y += 4;
		}
	}

	function cleanup(bp:Int) {
		var one = 3 << bp, y = 0;
		while (y < h) {
			var rows = h - y < 4 ? h - y : 4, i0 = (y + 1) * sw + 1, j0 = y * w;
			for (x in 0...w) {
				var r = 0, i = i0 + x, j = j0 + x;
				// (run-length mode: a full column of four, nothing significant or visited around it)
				if (rows == 4 && (fl[i] | fl[i + sw] | fl[i + 2 * sw] | (fl[i + 3 * sw] & vm)) == 0) {
					if (mq(17) == 0) continue;
					r = (mq(18) << 1) | mq(18);
					i += r * sw;
					j += r * w;
					var neg = signOf(fl[i] & (r < 3 ? 0xffff : vm));
					out[j] = neg != 0 ? -one : one;
					set(i, neg);
					r++;
					i += sw;
					j += w;
				}
				while (r < rows) {
					var f = fl[i] & (r < 3 ? 0xffff : vm);
					if (f & (SIG | VISIT) == 0 && mq(ZC[zo | (f & NB)]) != 0) {
						var neg = signOf(f);
						out[j] = neg != 0 ? -one : one;
						set(i, neg);
					}
					fl[i] &= ~VISIT;
					r++;
					i += sw;
					j += w;
				}
			}
			y += 4;
		}
	}
}
