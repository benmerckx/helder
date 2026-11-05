package helder.image;

import haxe.ds.Vector;
import haxe.io.Bytes;

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
	public static function decode(jpg:Bytes):{width:Int, height:Int, rgba:Bytes} {
		var r = new ByteReader(jpg);
		if (r.length < 4 || r.u8(0) != 0xFF || r.u8(1) != 0xD8) throw ImageError.unsupported("JpegDecoder: not a JPEG file");
		return ImageLimits.guard("JpegDecoder", () -> new JpegDecoder(jpg).run());
	}

	function new(data:Bytes)
		this.data = new ByteReader(data);

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
			bytes += (c.blocksX : Float) * c.blocksY * 64 * 5 + (width : Float) * height;
		}
		ImageLimits.memory("JpegDecoder", bytes + (width : Float) * height * 8);
		for (c in components)
			c.coeffs = new Vector<Int>(c.blocksX * c.blocksY * 64, 0);
	}

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
		var decodeBlock:(Component, Int) -> Void = if (!progressive) baseline else if (ss == 0) (ah == 0 ? (c, b) -> dcFirst(c, b, al) : (c, b) -> dcRefine(c, b, al)) else
			(ah == 0 ? (c, b) -> acFirst(c, b, ss, se, al) : (c, b) -> acRefine(c, b, ss, se, al));
		var units = 0, total:Int;
		if (scan.length == 1) {
			// non-interleaved: the component's own blocks, in rows
			var c = scan[0];
			var bx = Std.int((c.width + 7) / 8), by = Std.int((c.height + 7) / 8);
			total = bx * by;
			for (y in 0...by)
				for (x in 0...bx) {
					restart(units++);
					decodeBlock(c, y * c.blocksX + x);
				}
		} else {
			total = mcusX * mcusY;
			for (my in 0...mcusY)
				for (mx in 0...mcusX) {
					restart(units++);
					for (c in scan)
						for (v in 0...c.v)
							for (h in 0...c.h)
								decodeBlock(c, (my * c.v + v) * c.blocksX + mx * c.h + h);
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
		var ac = acTables[c.acTable];
		var k = 1;
		while (k < 64) {
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
			var q = quant[c.tq];
			if (q == null) throw "JpegDecoder: no quantization table " + c.tq;
			c.pixels = Bytes.alloc(c.blocksX * 8 * c.blocksY * 8);
			var ws = new Vector<Int>(64);
			for (by in 0...c.blocksY)
				for (bx in 0...c.blocksX)
					idct(c.coeffs, (by * c.blocksX + bx) * 64, q, ws, c.pixels, by * 8 * c.blocksX * 8 + bx * 8, c.blocksX * 8);
			c.coeffs = null;
		}
		// each component at the image's size
		var planes = [for (c in components) upsample(c)];
		var rgba = Bytes.alloc(width * height * 4);
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
		for (i in 0...width * height) {
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
		return orient(rgba);
	}

	// the component's samples upsampled to width x height (one byte each)
	function upsample(c:Component):Bytes {
		var stride = c.blocksX * 8, src = c.pixels;
		var rh = Std.int(hmax / c.h), rv = Std.int(vmax / c.v);
		var out = Bytes.alloc(width * height);
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
		for (y in 0...height) {
			// the source row (h1v2 fancy: blended with its nearer neighbour)
			var sy = Std.int(y / rv);
			var srcRow = new Vector<Int>(cw);
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
		return Exif.apply(rgba, width, height, orientation);

	// libjpeg's jpeg_idct_islow: a block's coefficients dequantized, columns then rows, into 8x8 samples
	static function idct(co:Vector<Int>, o:Int, q:Vector<Int>, ws:Vector<Int>, out:Bytes, at:Int, stride:Int) {
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
	public var coeffs:Null<Vector<Int>>;
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
	}
}
