package helder.image;

import haxe.ds.Vector;
import haxe.io.Bytes;
import hxmc.simd.*;

// JPEG files decoded to RGBA8 (Image.decode), as browsers decode them
// (libjpeg-turbo's way): baseline and extended sequential (SOF0, SOF1) and
// progressive (SOF2) Huffman-coded images, 8-bit samples; any sampling
// factors; restart intervals; greyscale, YCbCr (JFIF), RGB and CMYK or YCCK
// (Adobe's APP14, inverted as Photoshop writes it); the EXIF orientation
// applied. The inverse DCT is libjpeg's accurate integer one (jidctint),
// chroma is upsampled by its "fancy" triangle filters (h2v1, h2v2, h1v2;
// other ratios by replication) and converted by its fixed-point tables
// (jdcolor), so the pixels are libjpeg's. Lossless and arithmetic-coded
// JPEGs, 12-bit samples and colour profiles are not supported.
class JpegDecoder {
	static final ZIGZAG = [
		 0,  1,  8, 16,  9,  2,  3, 10, 17, 24, 32, 25, 18, 11,  4,  5,
		12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13,  6,  7, 14, 21, 28,
		35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
		58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63
	];

	final data:ByteReader;
	var pos = 0;
	final quant:Array<Null<Vector<Int>>> = [null, null, null, null];
	final dcTables:Array<Null<Huffman>> = [null, null, null, null];
	final acTables:Array<Null<Huffman>> = [null, null, null, null];
	final components:Array<Component> = [];
	var width = 0;
	var height = 0;
	var progressive = false;
	var hmax = 1;
	var vmax = 1;
	var mcusX = 0;
	var mcusY = 0;
	var restartInterval = 0;
	var adobe = -1; // APP14's transform (-1: none)
	var jfif = false;
	var orientation = 1;
	var frameRead = false;
	var scans = 0;
	// the bit reader
	var bitBuf = 0;
	var bitCount = 0;
	var eobrun = 0;
	var markerHit = false;

	// the pixels: width * height * 4 bytes, rows top to bottom, opaque
	// (mem: where its planes, coefficients and pixels are, ImageMemory;
	// scale 1, 2, 4 or 8: the image at that fraction of its size, each
	// block's IDCT reduced to 4x4, 2x2 or its DC, as libjpeg's scale_denom:
	// a photo decoded at the size it is shown, a fraction of the work)
	public static function decode(jpg:Bytes, ?mem:ImageMemory, scale = 1):{width:Int, height:Int, rgba:Bytes} {
		if (scale != 1 && scale != 2 && scale != 4 && scale != 8) throw ImageError.unsupported("JpegDecoder: a scale of 1/" + scale);
		var r = new ByteReader(jpg);
		if (r.length < 4 || r.u8(0) != 0xFF || r.u8(1) != 0xD8) throw ImageError.unsupported("JpegDecoder: not a JPEG file");
		return ImageLimits.guard("JpegDecoder", () -> {
			var d = new JpegDecoder(jpg, mem ?? ImageMemory.gc);
			d.bs = 8 >> (scale == 1 ? 0 : scale == 2 ? 1 : scale == 4 ? 2 : 3);
			d.run();
		});
	}

	// the largest reduction (1, 2, 4 or 8) whose image is still at least
	// w x h, of an image of width x height (as stored: EXIF's turn aside)
	public static function scaleFor(width:Int, height:Int, w:Int, h:Int):Int {
		var s = 8;
		while (s > 1 && (Math.ceil(width / s) < w || Math.ceil(height / s) < h))
			s >>= 1;
		return s;
	}

	final mem:ImageMemory;
	// a block's samples a side (8, or 4, 2, 1 scaled)
	var bs = 8;

	// the threads a decode's IDCT, upsampling and colours are split over
	// (natively; 1: the calling thread's alone)
	public static var threads = 1;

	function new(data:Bytes, mem:ImageMemory) {
		this.data = new ByteReader(data);
		this.mem = mem;
	}

	function u16(p:Int):Int
		return (data.u8(p) << 8) | data.u8(p + 1);

	function run():{width:Int, height:Int, rgba:Bytes} {
		pos = 2;
		var done = false;
		while (!done) {
			if (pos + 4 > data.length) {
				if (frameRead) break;
				throw "JpegDecoder: truncated";
			}
			if (data.u8(pos) != 0xFF) {
				pos++;
				continue;
			}
			var m = data.u8(pos + 1);
			pos += 2;
			if (m == 0xFF || m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
				if (m == 0xFF) pos--;
				continue;
			}
			if (m == 0xD9) break;
			var len = u16(pos), seg = pos + 2, end = pos + len;
			if (len < 2 || end > data.length) throw "JpegDecoder: a truncated segment";
			switch m {
				case 0xDB: readQuant(seg, end);
				case 0xC4: readHuffman(seg, end);
				case 0xDD: restartInterval = u16(seg);
				case 0xC0 | 0xC1 | 0xC2: readFrame(seg, end, m == 0xC2);
				case 0xC3 | 0xC5 | 0xC6 | 0xC7 | 0xC9 | 0xCA | 0xCB | 0xCD | 0xCE | 0xCF:
					throw ImageError.unsupported("JpegDecoder: lossless, hierarchical or arithmetic-coded JPEGs are not supported");
				case 0xE0:
					if (len >= 7 && data.string(seg, 4) == "JFIF") jfif = true;
				case 0xE1:
					if (len >= 8 && data.string(seg, 4) == "Exif" && orientation == 1) orientation = Exif.tiff(data.bytes, seg + 6, end);
				case 0xEE:
					if (len >= 14 && data.string(seg, 5) == "Adobe") adobe = data.u8(seg + 11);
				case 0xDA:
					pos = end;
					readScan(seg, end);
					continue;
				case _:
			}
			pos = end;
		}
		if (!frameRead) throw "JpegDecoder: no frame";
		// (a file cut before its first scan: nothing of the image, not a grey one)
		if (scans == 0) throw "JpegDecoder: no image data";
		return output();
	}

	function readQuant(p:Int, end:Int) {
		while (p < end) {
			var pq = data.u8(p) >> 4, tq = data.u8(p) & 15;
			p++;
			if (tq > 3) throw "JpegDecoder: a quantization table id " + tq;
			if (p + (pq == 0 ? 64 : 128) > end) throw "JpegDecoder: a quantization table cut short";
			var t = new Vector<Int>(64);
			for (i in 0...64) {
				t[ZIGZAG[i]] = pq == 0 ? data.u8(p) : u16(p);
				p += pq == 0 ? 1 : 2;
			}
			quant[tq] = t;
		}
	}

	function readHuffman(p:Int, end:Int) {
		while (p < end) {
			var tc = data.u8(p) >> 4, th = data.u8(p) & 15;
			if (th > 3) throw "JpegDecoder: a Huffman table id " + th;
			if (p + 17 > end) throw "JpegDecoder: a Huffman table cut short";
			var counts = [for (i in 0...16) data.u8(p + 1 + i)];
			var n = 0;
			// (no more codes of a length than it has: a table that fits)
			var room = 2;
			for (c in counts) {
				n += c;
				if (c > room) throw "JpegDecoder: a Huffman table of too many codes";
				room = (room - c) * 2;
			}
			if (p + 17 + n > end) throw "JpegDecoder: a Huffman table cut short";
			var symbols = [for (i in 0...n) data.u8(p + 17 + i)];
			var h = new Huffman(counts, symbols);
			if (tc == 0) dcTables[th] = h else acTables[th] = h;
			p += 17 + n;
		}
	}

	function readFrame(p:Int, end:Int, prog:Bool) {
		if (frameRead) throw "JpegDecoder: more than one frame";
		frameRead = true;
		progressive = prog;
		if (p + 6 > end) throw "JpegDecoder: a frame header cut short";
		if (data.u8(p) != 8) throw ImageError.unsupported("JpegDecoder: " + data.u8(p) + "-bit samples are not supported");
		height = u16(p + 1);
		width = u16(p + 3);
		if (width == 0 || height == 0) throw ImageError.unsupported("JpegDecoder: an image without a size (DNL) is not supported");
		// (the sides and pixels first: the sizes below are within an Int then)
		ImageLimits.check("JpegDecoder", width, height, 0);
		var n = data.u8(p + 5);
		if (n != 1 && n != 3 && n != 4) throw ImageError.unsupported("JpegDecoder: " + n + " components");
		if (p + 6 + 3 * n > end) throw "JpegDecoder: a frame header cut short";
		for (i in 0...n) {
			var q = p + 6 + 3 * i;
			var c = new Component(data.u8(q), data.u8(q + 1) >> 4, data.u8(q + 1) & 15, data.u8(q + 2));
			if (c.h < 1 || c.h > 4 || c.v < 1 || c.v > 4) throw ImageError.unsupported("JpegDecoder: sampling factors " + c.h + "x" + c.v);
			if (c.tq > 3) throw "JpegDecoder: a quantization table id " + c.tq;
			components.push(c);
			if (c.h > hmax) hmax = c.h;
			if (c.v > vmax) vmax = c.v;
		}
		mcusX = Std.int((width + 8 * hmax - 1) / (8 * hmax));
		mcusY = Std.int((height + 8 * vmax - 1) / (8 * vmax));
		// (the decode's memory: each component's coefficients (an Int each)
		// and samples, then its plane at the image's size, the pixels, and a
		// turned copy of them)
		var bytes = 0.0;
		for (c in components) {
			c.width = Std.int((width * c.h + hmax - 1) / hmax);
			c.height = Std.int((height * c.v + vmax - 1) / vmax);
			c.blocksX = mcusX * c.h;
			c.blocksY = mcusY * c.v;
			bytes += (c.blocksX : Float) * c.blocksY * 64 * 3 + (width : Float) * height;
		}
		ImageLimits.memory("JpegDecoder", bytes + (width : Float) * height * 8);
		// (scaled to 2x2 or 1x1 blocks and sequential: each block's reduced IDCT as it is
		// decoded, into its component's samples, no coefficients kept; else all of them,
		// for the IDCT after, in strips over threads)
		direct = !progressive && bs < 8;
		for (c in components)
			if (blockSize(c) > 2) direct = false;
		for (c in components) {
			c.bs = blockSize(c);
			if (direct) c.pixels = mem.bytes(c.blocksX * c.bs * c.blocksY * c.bs) else c.coeffs = new Coeffs(mem.bytes(c.blocksX * c.blocksY * 64 * 2));
		}
	}

	// (scaled: a subsampled component at a larger block where that spares it
	// upsampling, as libjpeg's jpeg_core_output_dimensions)
	function blockSize(c:Component):Int {
		var nb = bs;
		while (nb < 8 && (hmax * bs) % (c.h * nb * 2) == 0 && (vmax * bs) % (c.v * nb * 2) == 0)
			nb *= 2;
		return nb;
	}

	var direct = false;
	// (direct: a block's coefficients, the natural order, and which were set)
	final block = new Coeffs(Bytes.alloc(128));
	final touched = new Vector<Int>(64);
	var wsf = new Vector<Float>(64);
	final ws2 = new Vector<Int>(16);

	// --- scans ---

	function readScan(p:Int, end:Int) {
		if (!frameRead) throw "JpegDecoder: a scan before the frame";
		var n = data.u8(p);
		if (n < 1 || n > 4 || p + 4 + 2 * n > end) throw "JpegDecoder: a scan header cut short";
		scans++;
		var scan:Array<Component> = [];
		for (i in 0...n) {
			var id = data.u8(p + 1 + 2 * i), t = data.u8(p + 2 + 2 * i);
			var c:Null<Component> = null;
			for (k in components)
				if (k.id == id) c = k;
			if (c == null) throw "JpegDecoder: a scan of an unknown component";
			c.dcTable = t >> 4;
			c.acTable = t & 15;
			if (c.dcTable > 3 || c.acTable > 3) throw "JpegDecoder: a Huffman table id " + t;
			scan.push(c);
		}
		var q = p + 1 + 2 * n;
		var ss = data.u8(q), se = data.u8(q + 1), ah = data.u8(q + 2) >> 4, al = data.u8(q + 2) & 15;
		if (!progressive) {
			ss = 0;
			se = 63;
			ah = al = 0;
		}
		if (se > 63 || ss > se || al > 13) throw "JpegDecoder: a scan's spectral selection " + ss + "-" + se;
		for (c in scan) {
			c.pred = 0;
			var needDc = ss == 0 && ah == 0, needAc = !progressive || ss > 0;
			if ((needDc && dcTables[c.dcTable] == null) || (needAc && acTables[c.acTable] == null)) throw "JpegDecoder: a scan without its Huffman table";
		}
		bitBuf = bitCount = 0;
		eobrun = 0;
		markerHit = false;
		if (direct) for (c in scan)
			if (quant[c.tq] == null) throw "JpegDecoder: no quantization table " + c.tq;
		var decodeBlock:(Component, Int) -> Void = if (!progressive) baseline else if (ss == 0) (ah == 0 ? (c, b) -> dcFirst(c, b, al) : (c, b) -> dcRefine(c, b, al)) else
			(ah == 0 ? (c, b) -> acFirst(c, b, ss, se, al) : (c, b) -> acRefine(c, b, ss, se, al));
		var units = 0, total:Int;
		if (scan.length == 1) {
			// non-interleaved: the component's own blocks, in rows
			var c = scan[0];
			var bx = Std.int((c.width + 7) / 8), by = Std.int((c.height + 7) / 8);
			total = bx * by;
			for (y in 0...by) {
				GcPoint.poll();
				for (x in 0...bx) {
					restart(units++);
					if (direct) baselineDirect(c, x, y) else decodeBlock(c, y * c.blocksX + x);
				}
			}
		} else {
			total = mcusX * mcusY;
			for (my in 0...mcusY) {
				GcPoint.poll();
				for (mx in 0...mcusX) {
					restart(units++);
					for (c in scan)
						for (v in 0...c.v)
							for (h in 0...c.h)
								if (direct) baselineDirect(c, mx * c.h + h, my * c.v + v) else decodeBlock(c, (my * c.v + v) * c.blocksX + mx * c.h + h);
				}
			}
		}
		// past the scan's data: the next marker
		while (pos + 1 < data.length && !(data.u8(pos) == 0xFF && data.u8(pos + 1) != 0 && (data.u8(pos + 1) < 0xD0 || data.u8(pos + 1) > 0xD7)))
			pos++;
	}

	// before restart interval units: the bits realigned past an RSTn marker, the predictions reset
	function restart(units:Int) {
		if (restartInterval == 0 || units == 0 || units % restartInterval != 0) return;
		bitBuf = bitCount = 0;
		markerHit = false;
		while (pos + 1 < data.length && !(data.u8(pos) == 0xFF && data.u8(pos + 1) >= 0xD0 && data.u8(pos + 1) <= 0xD7))
			pos++;
		if (pos + 1 < data.length) pos += 2;
		for (c in components)
			c.pred = 0;
		eobrun = 0;
	}

	inline function fill() {
		while (bitCount <= 24) {
			var b = 0;
			if (!markerHit && pos < data.length) {
				b = data.u8(pos);
				if (b == 0xFF) {
					var n = pos + 1 < data.length ? data.u8(pos + 1) : 0;
					if (n == 0) pos += 2 else {
						// a marker: zeros from here
						markerHit = true;
						b = 0;
					}
				} else pos++;
			}
			bitBuf = (bitBuf << 8) | b;
			bitCount += 8;
		}
	}

	inline function bits(n:Int):Int {
		if (n == 0) return 0;
		if (bitCount < n) fill();
		bitCount -= n;
		return (bitBuf >>> bitCount) & ((1 << n) - 1);
	}

	inline function bit():Int
		return bits(1);

	// a received n-bit value as a signed coefficient
	inline function extend(v:Int, n:Int):Int
		return n == 0 ? 0 : v < 1 << (n - 1) ? v - (1 << n) + 1 : v;

	function huff(h:Huffman):Int {
		if (bitCount < 16) fill();
		var look = (bitBuf >>> (bitCount - 9)) & 511;
		var e = h.fast[look];
		if (e >= 0) {
			bitCount -= e >> 8;
			return e & 255;
		}
		var code = 0;
		for (l in 1...17) {
			code = (code << 1) | bit();
			if (code <= h.maxcode[l]) return h.symbols[h.valptr[l] + code - h.mincode[l]];
		}
		return 0; // (corrupt data: a zero)
	}

	function baseline(c:Component, b:Int) {
		var o = b * 64, co = c.coeffs;
		var t = huff(dcTables[c.dcTable]);
		c.pred += extend(bits(t), t);
		co[o] = c.pred;
		var ac = acTables[c.acTable], fastAc = ac.fastAc;
		var k = 1;
		while (k < 64) {
			if (bitCount < 16) fill();
			var f = fastAc[(bitBuf >>> (bitCount - 9)) & 511];
			if (f != 0) {
				bitCount -= f & 15;
				k += (f >> 4) & 15;
				if (k > 63) break;
				co[o + ZIGZAG[k]] = f >> 8;
				k++;
				continue;
			}
			var rs = huff(ac), s = rs & 15, r = rs >> 4;
			if (s == 0) {
				if (r != 15) break;
				k += 16;
				continue;
			}
			k += r;
			if (k > 63) break;
			co[o + ZIGZAG[k]] = extend(bits(s), s);
			k++;
		}
	}

	// a sequential block decoded at a reduced scale, its samples written now:
	// at 1/8 its DC alone (its AC codes read past), else its coefficients
	// into one block's buffer for the reduced IDCT (2x2: libjpeg's
	// jpeg_idct_2x2, the same integers; 4x4: reduced), then cleared again
	function baselineDirect(c:Component, bx:Int, by:Int) {
		var t = huff(dcTables[c.dcTable]);
		c.pred += extend(bits(t), t);
		var ac = acTables[c.acTable], q = quant[c.tq], nb = c.bs;
		var stride = c.blocksX * nb, at = by * nb * stride + bx * nb;
		var k = 1, fastAc = ac.fastAc;
		if (nb == 1) {
			// (the bit reader's state in locals for the loop: it is most of the work)
			var buf = bitBuf, cnt = bitCount, p = pos, len = data.length;
			while (k < 64) {
				if (cnt < 16) {
					while (cnt <= 24) {
						var x = 0;
						if (!markerHit && p < len) {
							x = data.u8(p);
							if (x == 0xFF) {
								if ((p + 1 < len ? data.u8(p + 1) : 0) == 0) p += 2 else {
									markerHit = true;
									x = 0;
								}
							} else p++;
						}
						buf = (buf << 8) | x;
						cnt += 8;
					}
				}
				var f = fastAc[(buf >>> (cnt - 9)) & 511];
				if (f != 0) {
					cnt -= f & 15;
					k += ((f >> 4) & 15) + 1;
					continue;
				}
				bitBuf = buf;
				bitCount = cnt;
				pos = p;
				var rs = huff(ac), s = rs & 15, r = rs >> 4;
				if (s == 0) {
					if (r != 15) {
						buf = bitBuf;
						cnt = bitCount;
						p = pos;
						break;
					}
					k += 16;
				} else {
					k += r + 1;
					if (bitCount < s) fill();
					bitCount -= s;
				}
				buf = bitBuf;
				cnt = bitCount;
				p = pos;
			}
			bitBuf = buf;
			bitCount = cnt;
			pos = p;
			// (libjpeg's jpeg_idct_1x1)
			var v = ((c.pred * q[0] + 4) >> 3) + 128;
			c.pixels.set(at, v < 0 ? 0 : v > 255 ? 255 : v);
			return;
		}
		var co = block, n = 0;
		co[0] = c.pred;
		touched[n++] = 0;
		while (k < 64) {
			if (bitCount < 16) fill();
			var f = fastAc[(bitBuf >>> (bitCount - 9)) & 511];
			if (f != 0) {
				bitCount -= f & 15;
				k += (f >> 4) & 15;
				if (k > 63) break;
				var z = ZIGZAG[k];
				co[z] = f >> 8;
				touched[n++] = z;
				k++;
				continue;
			}
			var rs = huff(ac), s = rs & 15, r = rs >> 4;
			if (s == 0) {
				if (r != 15) break;
				k += 16;
				continue;
			}
			k += r;
			if (k > 63) break;
			var z = ZIGZAG[k];
			co[z] = extend(bits(s), s);
			touched[n++] = z;
			k++;
		}
		if (nb == 2) idct2x2(co, q, ws2, c.pixels, at, stride) else reduced(co, 0, q, nb, table4, wsf, c.pixels, at, stride);
		for (i in 0...n)
			co[touched[i]] = 0;
	}

	static final table4 = reducedTable(4);

	// libjpeg's jpeg_idct_2x2 (jidctred.c, islow's constants): columns 0, 1,
	// 3, 5 and 7, then two rows; 2, 4 and 6 have no part in it. (Its sums
	// within 32 bits for a valid JPEG's coefficients, whose 8-bit samples'
	// dequantized values are within 2^11: libjpeg's are 64-bit.)
	static function idct2x2(co:Coeffs, q:Vector<Int>, ws:Vector<Int>, out:Bytes, at:Int, stride:Int) {
		inline function column(col:Int) {
			var c1 = co[8 + col], c3 = co[24 + col], c5 = co[40 + col], c7 = co[56 + col];
			if (c1 == 0 && c3 == 0 && c5 == 0 && c7 == 0) {
				var dc = (co[col] * q[col]) << 2;
				ws[col] = dc;
				ws[8 + col] = dc;
			} else {
				var tmp10 = (co[col] * q[col]) << 15;
				var tmp0 = c7 * q[56 + col] * -5906 + c5 * q[40 + col] * 6967 + c3 * q[24 + col] * -10426 + c1 * q[8 + col] * 29692;
				ws[col] = (tmp10 + tmp0 + 4096) >> 13;
				ws[8 + col] = (tmp10 - tmp0 + 4096) >> 13;
			}
		}
		column(0);
		column(1);
		column(3);
		column(5);
		column(7);
		inline function sample(v:Int):Int {
			var x = v + 128;
			return x < 0 ? 0 : x > 255 ? 255 : x;
		}
		inline function row(w:Int, o:Int) {
			var w1 = ws[w + 1], w3 = ws[w + 3], w5 = ws[w + 5], w7 = ws[w + 7];
			if (w1 == 0 && w3 == 0 && w5 == 0 && w7 == 0) {
				var v = sample((ws[w] + 16) >> 5);
				out.set(o, v);
				out.set(o + 1, v);
			} else {
				var tmp10 = ws[w] << 15;
				var tmp0 = w7 * -5906 + w5 * 6967 + w3 * -10426 + w1 * 29692;
				out.set(o, sample((tmp10 + tmp0 + (1 << 19)) >> 20));
				out.set(o + 1, sample((tmp10 - tmp0 + (1 << 19)) >> 20));
			}
		}
		row(0, at);
		row(8, at + stride);
	}

	function dcFirst(c:Component, b:Int, al:Int) {
		var t = huff(dcTables[c.dcTable]);
		c.pred += extend(bits(t), t);
		c.coeffs[b * 64] = c.pred << al;
	}

	function dcRefine(c:Component, b:Int, al:Int)
		if (bit() != 0) c.coeffs[b * 64] |= 1 << al;

	function acFirst(c:Component, b:Int, ss:Int, se:Int, al:Int) {
		if (eobrun > 0) {
			eobrun--;
			return;
		}
		var o = b * 64, co = c.coeffs, ac = acTables[c.acTable];
		var k = ss;
		while (k <= se) {
			var rs = huff(ac), s = rs & 15, r = rs >> 4;
			if (s == 0) {
				if (r < 15) {
					eobrun = (1 << r) - 1;
					if (r > 0) eobrun += bits(r);
					break;
				}
				k += 16;
				continue;
			}
			k += r;
			if (k > 63) break;
			co[o + ZIGZAG[k]] = extend(bits(s), s) * (1 << al);
			k++;
		}
	}

	function acRefine(c:Component, b:Int, ss:Int, se:Int, al:Int) {
		var o = b * 64, co = c.coeffs, ac = acTables[c.acTable];
		var p1 = 1 << al, m1 = -1 << al;
		var k = ss;
		if (eobrun == 0) {
			while (k <= se) {
				var rs = huff(ac), s = rs & 15, r = rs >> 4;
				if (s != 0) s = bit() != 0 ? p1 : m1 else if (r != 15) {
					eobrun = 1 << r;
					if (r > 0) eobrun += bits(r);
					break;
				}
				// past the coefficients already nonzero (their correction bits) and r zero ones
				while (k <= se) {
					var z = o + ZIGZAG[k];
					if (co[z] != 0) {
						if (bit() != 0 && co[z] & p1 == 0) co[z] += co[z] >= 0 ? p1 : m1;
					} else {
						if (r == 0) break;
						r--;
					}
					k++;
				}
				if (s != 0 && k <= se) co[o + ZIGZAG[k]] = s;
				k++;
			}
		}
		if (eobrun > 0) {
			while (k <= se) {
				var z = o + ZIGZAG[k];
				if (co[z] != 0 && bit() != 0 && co[z] & p1 == 0) co[z] += co[z] >= 0 ? p1 : m1;
				k++;
			}
			eobrun--;
		}
	}

	// --- pixels ---

	function output():{width:Int, height:Int, rgba:Bytes} {
		for (c in components) {
			// (decoded directly: its samples there already)
			if (direct) continue;
			var nb = blockSize(c);
			c.bs = nb;
			var table = nb < 8 ? reducedTable(nb) : null;
			var q = quant[c.tq];
			if (q == null) throw "JpegDecoder: no quantization table " + c.tq;
			c.pixels = mem.bytes(c.blocksX * nb * c.blocksY * nb);
			// (the table as 32-bit lanes, for the SIMD IDCT)
			var qb = Bytes.alloc(256);
			for (k in 0...64)
				qb.setInt32(4 * k, q[k]);
			// (in strips of block rows, each its own workspace)
			Strips.run(threads, c.blocksY, (from, to) -> {
				var wsf = new Vector<Float>(64), w1 = Bytes.alloc(256), w2 = Bytes.alloc(256);
				for (by in from...to)
					if (GcPoint.yes()) for (bx in 0...c.blocksX)
						if (nb == 8) idctSimd(c.coeffs.bytes(), (by * c.blocksX + bx) * 64, qb, w1, w2, c.pixels, by * 8 * c.blocksX * 8 + bx * 8, c.blocksX * 8) else
							reduced(c.coeffs, (by * c.blocksX + bx) * 64, q, nb, table, wsf, c.pixels, by * nb * c.blocksX * nb + bx * nb, c.blocksX * nb);
			});
			c.coeffs = null;
		}
		// (scaled: the image's size and the components' at their fractions, rounded up)
		if (bs < 8) {
			width = Std.int((width * bs + 7) / 8);
			height = Std.int((height * bs + 7) / 8);
			for (c in components) {
				c.width = Std.int((c.width * c.bs + 7) / 8);
				c.height = Std.int((c.height * c.bs + 7) / 8);
			}
		}
		// each component at the image's size
		var planes = [for (c in components) null];
		Strips.run(threads, components.length, (from, to) -> for (k in from...to) planes[k] = upsample(components[k]));
		var rgba = mem.bytes(width * height * 4);
		var n = components.length;
		// (jdapimin's guess: JFIF is YCbCr, else Adobe's transform, else
		// components named R, G, B are RGB)
		var rgbIds = n == 3 && components[0].id == 82 && components[1].id == 71 && components[2].id == 66;
		var transform = jfif ? 1 : adobe >= 0 ? adobe : rgbIds ? 0 : 1;
		var crR = new Vector<Int>(256), cbB = new Vector<Int>(256), crG = new Vector<Int>(256), cbG = new Vector<Int>(256);
		for (i in 0...256) {
			var x = i - 128;
			// (jdcolor's build_ycc_rgb_table: 16 fraction bits, ONE_HALF rounding)
			crR[i] = (91881 * x + 32768) >> 16;
			cbB[i] = (116130 * x + 32768) >> 16;
			crG[i] = -46802 * x;
			cbG[i] = -22554 * x + 32768;
		}
		inline function clamp(v:Int):Int
			return v < 0 ? 0 : v > 255 ? 255 : v;
		Strips.run(threads, height, (from, to) -> {
			var i = from * width, end = to * width;
			// (YCbCr, four pixels at once: jdcolor's tables as arithmetic, the same values;
			// each pixel's RGBA one 32-bit lane, A 255)
			if (n == 3 && transform == 1) {
				var p0 = planes[0], p1 = planes[1], p2 = planes[2];
				var k128 = I32x4.splat(128), half = I32x4.splat(32768), zero = I32x4.zero(), max = I32x4.splat(255), alpha = I32x4.splat(0xFF000000);
				var cR = I32x4.splat(91881), cB = I32x4.splat(116130), gB = I32x4.splat(-22554), gR = I32x4.splat(-46802);
				while (i + 4 <= end) {
					if (i & 0xFFFF < 4) GcPoint.poll();
					var y = U32x4.extendLow(U16x8.extendLow(U8x16.load32(p0, i))).asI32x4();
					var cb = U32x4.extendLow(U16x8.extendLow(U8x16.load32(p1, i))).asI32x4() - k128;
					var cr = U32x4.extendLow(U16x8.extendLow(U8x16.load32(p2, i))).asI32x4() - k128;
					var r = (y + ((cr * cR + half) >> 16)).clamp(zero, max);
					var g = (y + ((cb * gB + half + cr * gR) >> 16)).clamp(zero, max);
					var b = (y + ((cb * cB + half) >> 16)).clamp(zero, max);
					(r | (g << 8) | (b << 16) | alpha).store(rgba, 4 * i);
					i += 4;
				}
			}
			for (i in i...end) {
			if (i & 0xFFFF == 0) GcPoint.poll();
			var r:Int, g:Int, b:Int;
			if (n == 1) {
				r = g = b = planes[0].get(i);
			} else if (n == 3) {
				var y = planes[0].get(i), cb = planes[1].get(i), cr = planes[2].get(i);
				if (transform == 1) {
					r = clamp(y + crR[cr]);
					g = clamp(y + ((cbG[cb] + crG[cr]) >> 16));
					b = clamp(y + cbB[cb]);
				} else {
					r = y;
					g = cb;
					b = cr;
				}
			} else {
				var c0 = planes[0].get(i), c1 = planes[1].get(i), c2 = planes[2].get(i), k = planes[3].get(i);
				if (adobe == 2) {
					// YCCK: YCbCr to (inverted) CMY first
					var y = c0, cb = c1, cr = c2;
					c0 = 255 - clamp(y + crR[cr]);
					c1 = 255 - clamp(y + ((cbG[cb] + crG[cr]) >> 16));
					c2 = 255 - clamp(y + cbB[cb]);
				}
				// (inverted CMYK, as Photoshop writes it: R = C K / 255)
				r = Std.int(c0 * k / 255);
				g = Std.int(c1 * k / 255);
				b = Std.int(c2 * k / 255);
			}
			rgba.set(4 * i, r);
			rgba.set(4 * i + 1, g);
			rgba.set(4 * i + 2, b);
			rgba.set(4 * i + 3, 255);
			}
		});
		return orient(rgba);
	}

	// the component's samples upsampled to width x height (one byte each)
	function upsample(c:Component):Bytes {
		var stride = c.blocksX * c.bs, src = c.pixels;
		var rh = Std.int(hmax * bs / (c.h * c.bs)), rv = Std.int(vmax * bs / (c.v * c.bs));
		var out = mem.bytes(width * height);
		var cw = c.width, ch = c.height;
		if (rh == 1 && rv == 1) {
			for (y in 0...height)
				out.blit(y * width, src, y * stride, width);
			return out;
		}
		// rows at the component's size, horizontally upsampled first
		inline function at(x:Int, y:Int):Int
			return src.get((y < 0 ? 0 : y >= ch ? ch - 1 : y) * stride + x);
		var fancyH = rh == 2 && cw > 2, fancyV = rv == 2;
		if (rh == 2 && rv == 2 && fancyH) {
			// h2v2: column sums of the row and its nearer neighbour, then across
			var outW = cw * 2;
			var row = new Vector<Int>(outW);
			for (y in 0...height) {
				GcPoint.poll();
				var sy = y >> 1, nb = (y & 1) == 0 ? sy - 1 : sy + 1;
				var last = 0, cur = at(0, sy) * 3 + at(0, nb), next = at(1, sy) * 3 + at(1, nb);
				row[0] = (cur * 4 + 8) >> 4;
				row[1] = (cur * 3 + next + 7) >> 4;
				last = cur;
				cur = next;
				for (x in 1...cw - 1) {
					next = at(x + 1, sy) * 3 + at(x + 1, nb);
					row[2 * x] = (cur * 3 + last + 8) >> 4;
					row[2 * x + 1] = (cur * 3 + next + 7) >> 4;
					last = cur;
					cur = next;
				}
				row[2 * cw - 2] = (cur * 3 + last + 8) >> 4;
				row[2 * cw - 1] = (cur * 4 + 7) >> 4;
				for (x in 0...width)
					out.set(y * width + x, row[x]);
			}
			return out;
		}
		var line = new Vector<Int>(cw * rh);
		var srcRow = new Vector<Int>(cw);
		for (y in 0...height) {
			GcPoint.poll();
			// the source row (h1v2 fancy: blended with its nearer neighbour)
			var sy = Std.int(y / rv);
			if (rv == 2 && fancyV && rh == 1) {
				var nb = (y & 1) == 0 ? sy - 1 : sy + 1, bias = (y & 1) == 0 ? 1 : 2;
				for (x in 0...cw)
					srcRow[x] = (at(x, sy) * 3 + at(x, nb) + bias) >> 2;
			} else
				for (x in 0...cw)
					srcRow[x] = at(x, sy);
			if (rh == 2 && fancyH && rv == 1) {
				// h2v1: the triangle filter across
				line[0] = srcRow[0];
				line[1] = (srcRow[0] * 3 + srcRow[1] + 2) >> 2;
				for (x in 1...cw - 1) {
					var v = srcRow[x] * 3;
					line[2 * x] = (v + srcRow[x - 1] + 1) >> 2;
					line[2 * x + 1] = (v + srcRow[x + 1] + 2) >> 2;
				}
				line[2 * cw - 2] = (srcRow[cw - 1] * 3 + srcRow[cw - 2] + 1) >> 2;
				line[2 * cw - 1] = srcRow[cw - 1];
			} else
				for (x in 0...cw * rh)
					line[x] = srcRow[Std.int(x / rh)];
			for (x in 0...width)
				out.set(y * width + x, line[x < cw * rh ? x : cw * rh - 1]);
		}
		return out;
	}

	// EXIF's orientation applied (2-8: mirrored, rotated)
	function orient(rgba:Bytes):{width:Int, height:Int, rgba:Bytes}
		return Exif.apply(rgba, width, height, orientation, mem);

	// (a reduced IDCT's basis: n x 8, C(u) cos((2x + 1) u pi / 2n) / 2: the
	// 8-point IDCT sampled at the centres of each group of 8 / n samples,
	// every coefficient's part in it, as libjpeg's jidctred)
	static function reducedTable(n:Int):Vector<Float> {
		var t = new Vector<Float>(n * 8);
		for (x in 0...n)
			for (u in 0...8)
				t[x * 8 + u] = (u == 0 ? Math.sqrt(0.5) : 1.0) * Math.cos((2 * x + 1) * u * Math.PI / (2 * n)) / 2;
		return t;
	}

	// a block's n x n samples (n 4, 2 or 1): its rows' n samples first, then the columns'
	static function reduced(co:Coeffs, o:Int, q:Vector<Int>, n:Int, t:Vector<Float>, ws:Vector<Float>, out:Bytes, at:Int, stride:Int) {
		if (n == 1) {
			// (the DC alone: libjpeg's jpeg_idct_1x1)
			var v = ((co[o] * q[0] + 4) >> 3) + 128;
			out.set(at, v < 0 ? 0 : v > 255 ? 255 : v);
			return;
		}
		for (v in 0...8)
			for (x in 0...n) {
				var sum = 0.0;
				for (u in 0...8)
					sum += t[x * 8 + u] * co[o + v * 8 + u] * q[v * 8 + u];
				ws[v * n + x] = sum;
			}
		for (y in 0...n)
			for (x in 0...n) {
				var sum = 0.0;
				for (v in 0...8)
					sum += t[y * 8 + v] * ws[v * n + x];
				var p = Math.round(sum) + 128;
				out.set(at + y * stride + x, p < 0 ? 0 : p > 255 ? 255 : p);
			}
	}

	// jpeg_idct_islow four columns (then four rows) at once, its integer
	// arithmetic lane by lane (the same samples as idct): the coefficients
	// dequantized into w1, the columns' pass into w2, transposed into w1,
	// the rows' pass (as columns of the transpose), transposed back as rows
	static function idctSimd(co:Bytes, o:Int, qb:Bytes, w1:Bytes, w2:Bytes, out:Bytes, at:Int, stride:Int) {
		for (k in 0...16)
			(I32x4.extendLow(I16x8.load64(co, 2 * (o + 4 * k))) * I32x4.load(qb, 16 * k)).store(w1, 16 * k);
		pass(w1, w2, 11);
		transpose(w2, w1);
		pass(w1, w2, 18);
		// (w2's rows are the transpose's: columns of the output; transposed as they are stored)
		var k128 = I32x4.splat(128), zero = I32x4.zero(), max = I32x4.splat(255);
		for (g in 0...2) {
			// (4 rows of the output: the transpose of w2's 4x4 tiles at rows 0-7, columns 4g..4g+3)
			var a0 = I32x4.load(w2, 16 * (0 * 2 + g)), a1 = I32x4.load(w2, 16 * (1 * 2 + g)), a2 = I32x4.load(w2, 16 * (2 * 2 + g)), a3 = I32x4.load(w2, 16 * (3 * 2 + g));
			var b0 = I32x4.load(w2, 16 * (4 * 2 + g)), b1 = I32x4.load(w2, 16 * (5 * 2 + g)), b2 = I32x4.load(w2, 16 * (6 * 2 + g)), b3 = I32x4.load(w2, 16 * (7 * 2 + g));
			var t0 = a0.shuffle(a1, 0, 4, 1, 5), t1 = a0.shuffle(a1, 2, 6, 3, 7), t2 = a2.shuffle(a3, 0, 4, 1, 5), t3 = a2.shuffle(a3, 2, 6, 3, 7);
			var u0 = b0.shuffle(b1, 0, 4, 1, 5), u1 = b0.shuffle(b1, 2, 6, 3, 7), u2 = b2.shuffle(b3, 0, 4, 1, 5), u3 = b2.shuffle(b3, 2, 6, 3, 7);
			inline function put(r:Int, lo:I32x4, hi:I32x4)
				U8x16.narrow(U16x8.narrow((lo + k128).clamp(zero, max), (hi + k128).clamp(zero, max)).asI16x8(), I16x8.zero()).store64(out, at + (4 * g + r) * stride);
			put(0, t0.shuffle(t2, 0, 1, 4, 5), u0.shuffle(u2, 0, 1, 4, 5));
			put(1, t0.shuffle(t2, 2, 3, 6, 7), u0.shuffle(u2, 2, 3, 6, 7));
			put(2, t1.shuffle(t3, 0, 1, 4, 5), u1.shuffle(u3, 0, 1, 4, 5));
			put(3, t1.shuffle(t3, 2, 3, 6, 7), u1.shuffle(u3, 2, 3, 6, 7));
		}
	}

	// (8x8 Int32s, row-major: src's columns' 1-D IDCT into dst, four columns
	// at a time; the result descaled by `bits`)
	static inline function pass(src:Bytes, dst:Bytes, bits:Int) {
		var round = I32x4.splat(1 << (bits - 1));
		for (g in 0...2) {
			inline function at(k:Int):I32x4
				return I32x4.load(src, 16 * (k * 2 + g));
			var z2 = at(2), z3 = at(6);
			var z1 = (z2 + z3) * I32x4.splat(4433);
			var tmp2 = z1 + z3 * I32x4.splat(-15137), tmp3 = z1 + z2 * I32x4.splat(6270);
			z2 = at(0);
			z3 = at(4);
			var tmp0 = (z2 + z3) << 13, tmp1 = (z2 - z3) << 13;
			var tmp10 = tmp0 + tmp3, tmp13 = tmp0 - tmp3, tmp11 = tmp1 + tmp2, tmp12 = tmp1 - tmp2;
			tmp0 = at(7);
			tmp1 = at(5);
			tmp2 = at(3);
			tmp3 = at(1);
			z1 = tmp0 + tmp3;
			z2 = tmp1 + tmp2;
			z3 = tmp0 + tmp2;
			var z4 = tmp1 + tmp3;
			var z5 = (z3 + z4) * I32x4.splat(9633);
			tmp0 = tmp0 * I32x4.splat(2446);
			tmp1 = tmp1 * I32x4.splat(16819);
			tmp2 = tmp2 * I32x4.splat(25172);
			tmp3 = tmp3 * I32x4.splat(12299);
			z1 = z1 * I32x4.splat(-7373);
			z2 = z2 * I32x4.splat(-20995);
			z3 = z3 * I32x4.splat(-16069) + z5;
			z4 = z4 * I32x4.splat(-3196) + z5;
			tmp0 = tmp0 + z1 + z3;
			tmp1 = tmp1 + z2 + z4;
			tmp2 = tmp2 + z2 + z3;
			tmp3 = tmp3 + z1 + z4;
			inline function put(k:Int, v:I32x4)
				((v + round) >> bits).store(dst, 16 * (k * 2 + g));
			put(0, tmp10 + tmp3);
			put(7, tmp10 - tmp3);
			put(1, tmp11 + tmp2);
			put(6, tmp11 - tmp2);
			put(2, tmp12 + tmp1);
			put(5, tmp12 - tmp1);
			put(3, tmp13 + tmp0);
			put(4, tmp13 - tmp0);
		}
	}

	// (8x8 Int32s, row-major: src transposed into dst, by 4x4 tiles)
	static inline function transpose(src:Bytes, dst:Bytes) {
		for (bi in 0...2)
			for (bj in 0...2) {
				inline function row(r:Int):I32x4
					return I32x4.load(src, 16 * ((4 * bi + r) * 2 + bj));
				var r0 = row(0), r1 = row(1), r2 = row(2), r3 = row(3);
				var t0 = r0.shuffle(r1, 0, 4, 1, 5), t1 = r0.shuffle(r1, 2, 6, 3, 7), t2 = r2.shuffle(r3, 0, 4, 1, 5), t3 = r2.shuffle(r3, 2, 6, 3, 7);
				t0.shuffle(t2, 0, 1, 4, 5).store(dst, 16 * ((4 * bj + 0) * 2 + bi));
				t0.shuffle(t2, 2, 3, 6, 7).store(dst, 16 * ((4 * bj + 1) * 2 + bi));
				t1.shuffle(t3, 0, 1, 4, 5).store(dst, 16 * ((4 * bj + 2) * 2 + bi));
				t1.shuffle(t3, 2, 3, 6, 7).store(dst, 16 * ((4 * bj + 3) * 2 + bi));
			}
	}

	// libjpeg's jpeg_idct_islow: a block's coefficients dequantized, columns then rows, into 8x8 samples
	static function idct(co:Coeffs, o:Int, q:Vector<Int>, ws:Vector<Int>, out:Bytes, at:Int, stride:Int) {
		inline function descale(x:Int, n:Int):Int
			return (x + (1 << (n - 1))) >> n;
		for (col in 0...8) {
			var i = o + col;
			if (co[i + 8] == 0 && co[i + 16] == 0 && co[i + 24] == 0 && co[i + 32] == 0 && co[i + 40] == 0 && co[i + 48] == 0 && co[i + 56] == 0) {
				var dc = (co[i] * q[col]) << 2;
				for (r in 0...8)
					ws[r * 8 + col] = dc;
				continue;
			}
			var z2 = co[i + 16] * q[16 + col], z3 = co[i + 48] * q[48 + col];
			var z1 = (z2 + z3) * 4433;
			var tmp2 = z1 + z3 * -15137, tmp3 = z1 + z2 * 6270;
			z2 = co[i] * q[col];
			z3 = co[i + 32] * q[32 + col];
			var tmp0 = (z2 + z3) << 13, tmp1 = (z2 - z3) << 13;
			var tmp10 = tmp0 + tmp3, tmp13 = tmp0 - tmp3, tmp11 = tmp1 + tmp2, tmp12 = tmp1 - tmp2;
			tmp0 = co[i + 56] * q[56 + col];
			tmp1 = co[i + 40] * q[40 + col];
			tmp2 = co[i + 24] * q[24 + col];
			tmp3 = co[i + 8] * q[8 + col];
			z1 = tmp0 + tmp3;
			z2 = tmp1 + tmp2;
			z3 = tmp0 + tmp2;
			var z4 = tmp1 + tmp3;
			var z5 = (z3 + z4) * 9633;
			tmp0 *= 2446;
			tmp1 *= 16819;
			tmp2 *= 25172;
			tmp3 *= 12299;
			z1 *= -7373;
			z2 *= -20995;
			z3 *= -16069;
			z4 *= -3196;
			z3 += z5;
			z4 += z5;
			tmp0 += z1 + z3;
			tmp1 += z2 + z4;
			tmp2 += z2 + z3;
			tmp3 += z1 + z4;
			ws[col] = descale(tmp10 + tmp3, 11);
			ws[56 + col] = descale(tmp10 - tmp3, 11);
			ws[8 + col] = descale(tmp11 + tmp2, 11);
			ws[48 + col] = descale(tmp11 - tmp2, 11);
			ws[16 + col] = descale(tmp12 + tmp1, 11);
			ws[40 + col] = descale(tmp12 - tmp1, 11);
			ws[24 + col] = descale(tmp13 + tmp0, 11);
			ws[32 + col] = descale(tmp13 - tmp0, 11);
		}
		inline function sample(v:Int):Int {
			var s = v + 128;
			return s < 0 ? 0 : s > 255 ? 255 : s;
		}
		for (row in 0...8) {
			var w = row * 8, p = at + row * stride;
			var z2 = ws[w + 2], z3 = ws[w + 6];
			var z1 = (z2 + z3) * 4433;
			var tmp2 = z1 + z3 * -15137, tmp3 = z1 + z2 * 6270;
			var tmp0 = (ws[w] + ws[w + 4]) << 13, tmp1 = (ws[w] - ws[w + 4]) << 13;
			var tmp10 = tmp0 + tmp3, tmp13 = tmp0 - tmp3, tmp11 = tmp1 + tmp2, tmp12 = tmp1 - tmp2;
			tmp0 = ws[w + 7];
			tmp1 = ws[w + 5];
			tmp2 = ws[w + 3];
			tmp3 = ws[w + 1];
			z1 = tmp0 + tmp3;
			z2 = tmp1 + tmp2;
			z3 = tmp0 + tmp2;
			var z4 = tmp1 + tmp3;
			var z5 = (z3 + z4) * 9633;
			tmp0 *= 2446;
			tmp1 *= 16819;
			tmp2 *= 25172;
			tmp3 *= 12299;
			z1 *= -7373;
			z2 *= -20995;
			z3 *= -16069;
			z4 *= -3196;
			z3 += z5;
			z4 += z5;
			tmp0 += z1 + z3;
			tmp1 += z2 + z4;
			tmp2 += z2 + z3;
			tmp3 += z1 + z4;
			out.set(p, sample(descale(tmp10 + tmp3, 18)));
			out.set(p + 7, sample(descale(tmp10 - tmp3, 18)));
			out.set(p + 1, sample(descale(tmp11 + tmp2, 18)));
			out.set(p + 6, sample(descale(tmp11 - tmp2, 18)));
			out.set(p + 2, sample(descale(tmp12 + tmp1, 18)));
			out.set(p + 5, sample(descale(tmp12 - tmp1, 18)));
			out.set(p + 3, sample(descale(tmp13 + tmp0, 18)));
			out.set(p + 4, sample(descale(tmp13 - tmp0, 18)));
		}
	}
}

private class Component {
	public final id:Int;
	public final h:Int;
	public final v:Int;
	public final tq:Int;
	// its size in samples, and in blocks (whole MCUs)
	public var width = 0;
	public var height = 0;
	public var blocksX = 0;
	public var blocksY = 0;
	public var coeffs:Null<Coeffs>;
	// its block's samples a side (8; scaled, 4, 2 or 1, or more than the image's)
	public var bs = 8;
	public var pixels:Null<Bytes>;
	public var dcTable = 0;
	public var acTable = 0;
	public var pred = 0;

	public function new(id, h, v, tq) {
		this.id = id;
		this.h = h;
		this.v = v;
		this.tq = tq;
	}
}

// a Huffman table: codes of up to 9 bits by lookup (length << 8 | symbol;
// -1: longer), the longer ones by length (maxcode, mincode, valptr)
private class Huffman {
	public final fast = new Vector<Int>(512, -1);
	// (an AC code and its value's bits within 9: value << 8 | run << 4 | the bits taken; 0: not)
	public final fastAc = new Vector<Int>(512, 0);
	public final maxcode = new Vector<Int>(18, -1);
	public final mincode = new Vector<Int>(17, 0);
	public final valptr = new Vector<Int>(17, 0);
	public final symbols:Array<Int>;

	public function new(counts:Array<Int>, symbols:Array<Int>) {
		this.symbols = symbols;
		var code = 0, k = 0;
		for (l in 1...17) {
			var n = counts[l - 1];
			valptr[l] = k;
			mincode[l] = code;
			for (i in 0...n) {
				if (l <= 9) {
					var shift = 9 - l;
					for (j in 0...1 << shift)
						fast[(code << shift) | j] = (l << 8) | symbols[k];
				}
				code++;
				k++;
			}
			maxcode[l] = n > 0 ? code - 1 : -1;
			code <<= 1;
		}
		maxcode[17] = 0x7FFFFFFF;
		// (stb_image's fast AC: a short code and its value's bits read at once)
		for (look in 0...512) {
			var e = fast[look];
			if (e < 0) continue;
			var l = e >> 8, rs = e & 255, r = rs >> 4, s = rs & 15;
			if (s == 0 || l + s > 9) continue;
			var v = (look >> (9 - l - s)) & ((1 << s) - 1);
			if (v < 1 << (s - 1)) v -= (1 << s) - 1;
			fastAc[look] = (v << 8) | (r << 4) | (l + s);
		}
	}
}

// a component's coefficients: 16 bits each (libjpeg's JCOEF), signed
abstract Coeffs(Bytes) {
	public inline function new(b:Bytes)
		this = b;

	@:arrayAccess inline function get(i:Int):Int
		return (this.getUInt16(i << 1) << 16) >> 16;

	public inline function bytes():Bytes
		return this;

	@:arrayAccess inline function set(i:Int, v:Int):Int {
		this.setUInt16(i << 1, v & 0xFFFF);
		return v;
	}
}
