package helder.image;

import haxe.ds.Vector;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;

// A baseline JPEG encoder (after stb_image_write's, Jon Olick's): YCbCr
// 4:4:4, the standard tables of ITU T.81's annex K scaled by the quality
// as libjpeg scales them (1 to 100), a floating-point AAN forward DCT, the
// standard Huffman codes. Straight RGBA in; alpha composited over a
// background colour (0xRRGGBB), JPEG having none.
class JpegEncoder {
	static final ZIGZAG = [
		0, 1, 5, 6, 14, 15, 27, 28, 2, 4, 7, 13, 16, 26, 29, 42, 3, 8, 12, 17, 25, 30, 41, 43, 9, 11, 18, 24, 31, 40, 44, 53, 10, 19, 23, 32, 39, 45,
		52, 54, 20, 22, 33, 38, 46, 51, 55, 60, 21, 34, 37, 47, 50, 56, 59, 61, 35, 36, 48, 49, 57, 58, 62, 63
	];
	static final Y_QT = [
		16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29, 51, 87, 80, 62, 18, 22, 37, 56,
		68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92, 49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99
	];
	static final UV_QT = [
		17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99, 24, 26, 56, 99, 99, 99, 99, 99, 47, 66, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
		99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99
	];
	static final DC_LUM_COUNTS = [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0];
	static final DC_LUM_VALUES = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
	static final AC_LUM_COUNTS = [0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7d];
	static final AC_LUM_VALUES = [
		0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xa1, 0x08,
		0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28,
		0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
		0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
		0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6,
		0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2,
		0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa
	];
	static final DC_CHR_COUNTS = [0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0];
	static final DC_CHR_VALUES = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
	static final AC_CHR_COUNTS = [0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77];
	static final AC_CHR_VALUES = [
		0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91,
		0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0, 0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16, 0x24, 0x34, 0xe1, 0x25, 0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26,
		0x27, 0x28, 0x29, 0x2a, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
		0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
		0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4,
		0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda,
		0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa
	];
	static final AAN = [1.0, 1.387039845, 1.306562965, 1.175875602, 1.0, 0.785694958, 0.541196100, 0.275899379];

	final out = new BytesBuffer();
	var bitBuf = 0;
	var bitCnt = 0;

	function new() {}

	public static function encode(rgba:Bytes, width:Int, height:Int, quality = 92, background = 0):Bytes
		return new JpegEncoder().run(rgba, width, height, quality, background);

	function run(rgba:Bytes, width:Int, height:Int, quality:Int, background:Int):Bytes {
		if (quality < 1) quality = 1;
		if (quality > 100) quality = 100;
		var scale = quality < 50 ? Std.int(5000 / quality) : 200 - quality * 2;
		var yq = new Vector<Int>(64), uq = new Vector<Int>(64);
		for (i in 0...64) {
			yq[ZIGZAG[i]] = clampQ(Std.int((Y_QT[i] * scale + 50) / 100));
			uq[ZIGZAG[i]] = clampQ(Std.int((UV_QT[i] * scale + 50) / 100));
		}
		// (the divisors with the AAN scale in, in natural order)
		var fy = new Vector<Float>(64), fu = new Vector<Float>(64);
		for (r in 0...8)
			for (c in 0...8) {
				var k = r * 8 + c;
				fy[k] = 1 / (yq[ZIGZAG[k]] * AAN[r] * AAN[c] * 8);
				fu[k] = 1 / (uq[ZIGZAG[k]] * AAN[r] * AAN[c] * 8);
			}
		// SOI, APP0 (JFIF), DQT, SOF0, DHT, SOS
		bytes([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 0x4A, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]);
		bytes([0xFF, 0xDB, 0, 0x84, 0]);
		for (i in 0...64)
			out.addByte(yq[i]);
		out.addByte(1);
		for (i in 0...64)
			out.addByte(uq[i]);
		bytes([0xFF, 0xC0, 0, 17, 8, height >> 8, height & 255, width >> 8, width & 255, 3, 1, 0x11, 0, 2, 0x11, 1, 3, 0x11, 1]);
		bytes([0xFF, 0xC4, 0x01, 0xA2]);
		table(0x00, DC_LUM_COUNTS, DC_LUM_VALUES);
		table(0x10, AC_LUM_COUNTS, AC_LUM_VALUES);
		table(0x01, DC_CHR_COUNTS, DC_CHR_VALUES);
		table(0x11, AC_CHR_COUNTS, AC_CHR_VALUES);
		bytes([0xFF, 0xDA, 0, 12, 3, 1, 0, 2, 0x11, 3, 0x11, 0, 63, 0]);
		var dcl = codes(DC_LUM_COUNTS, DC_LUM_VALUES), acl = codes(AC_LUM_COUNTS, AC_LUM_VALUES);
		var dcc = codes(DC_CHR_COUNTS, DC_CHR_VALUES), acc = codes(AC_CHR_COUNTS, AC_CHR_VALUES);
		var by = new Vector<Float>(64), bu = new Vector<Float>(64), bv = new Vector<Float>(64);
		var pY = 0, pU = 0, pV = 0;
		var br = (background >> 16) & 255, bg = (background >> 8) & 255, bb = background & 255;
		var y = 0;
		while (y < height) {
			var x = 0;
			while (x < width) {
				for (r in 0...8)
					for (c in 0...8) {
						var sy = y + r < height ? y + r : height - 1, sx = x + c < width ? x + c : width - 1;
						var o = (sy * width + sx) * 4, a = rgba.get(o + 3);
						var R = (rgba.get(o) * a + br * (255 - a)) / 255, G = (rgba.get(o + 1) * a + bg * (255 - a)) / 255,
							B = (rgba.get(o + 2) * a + bb * (255 - a)) / 255;
						var k = r * 8 + c;
						by[k] = 0.299 * R + 0.587 * G + 0.114 * B - 128;
						bu[k] = -0.16874 * R - 0.33126 * G + 0.5 * B;
						bv[k] = 0.5 * R - 0.41869 * G - 0.08131 * B;
					}
				pY = block(by, fy, pY, dcl, acl);
				pU = block(bu, fu, pU, dcc, acc);
				pV = block(bv, fu, pV, dcc, acc);
				x += 8;
			}
			y += 8;
		}
		// (the last bits padded with ones)
		bits(0x7F, 7);
		bytes([0xFF, 0xD9]);
		return out.getBytes();
	}

	static inline function clampQ(v:Int):Int
		return v < 1 ? 1 : v > 255 ? 255 : v;

	function bytes(a:Array<Int>)
		for (b in a)
			out.addByte(b & 255);

	function table(id:Int, counts:Array<Int>, values:Array<Int>) {
		out.addByte(id);
		for (c in counts)
			out.addByte(c);
		for (v in values)
			out.addByte(v);
	}

	// (each symbol's code and length: code << 8 | length, by symbol)
	static function codes(counts:Array<Int>, values:Array<Int>):Vector<Int> {
		var t = new Vector<Int>(256), code = 0, k = 0;
		for (i in 0...256)
			t[i] = 0;
		for (len in 1...17) {
			for (_ in 0...counts[len - 1]) {
				t[values[k++]] = (code << 8) | len;
				code++;
			}
			code <<= 1;
		}
		return t;
	}

	function bits(v:Int, n:Int) {
		bitBuf = (bitBuf << n) | (v & ((1 << n) - 1));
		bitCnt += n;
		while (bitCnt >= 8) {
			var b = (bitBuf >> (bitCnt - 8)) & 255;
			out.addByte(b);
			if (b == 0xFF) out.addByte(0);
			bitCnt -= 8;
		}
		bitBuf &= (1 << bitCnt) - 1;
	}

	inline function huff(t:Vector<Int>, sym:Int)
		bits(t[sym] >> 8, t[sym] & 255);

	// a block's DCT, quantized, coded; its DC returned (the next one's prediction)
	function block(b:Vector<Float>, f:Vector<Float>, pred:Int, dc:Vector<Int>, ac:Vector<Int>):Int {
		for (r in 0...8)
			dct(b, r * 8, 1);
		for (c in 0...8)
			dct(b, c, 8);
		var q = new Vector<Int>(64);
		for (i in 0...64) {
			var v = b[i] * f[i];
			q[ZIGZAG[i]] = Std.int(v < 0 ? Math.ceil(v - 0.5) : Math.floor(v + 0.5));
		}
		var diff = q[0] - pred;
		if (diff == 0) huff(dc, 0) else {
			var n = magnitude(diff);
			huff(dc, n);
			bits(diff < 0 ? diff - 1 : diff, n);
		}
		var last = 63;
		while (last > 0 && q[last] == 0)
			last--;
		if (last == 0) {
			huff(ac, 0);
			return q[0];
		}
		var i = 1;
		while (i <= last) {
			var start = i;
			while (q[i] == 0 && i <= last)
				i++;
			var zeros = i - start;
			while (zeros >= 16) {
				huff(ac, 0xF0);
				zeros -= 16;
			}
			var v = q[i], n = magnitude(v);
			huff(ac, (zeros << 4) | n);
			bits(v < 0 ? v - 1 : v, n);
			i++;
		}
		if (last != 63) huff(ac, 0);
		return q[0];
	}

	static inline function magnitude(v:Int):Int {
		var a = v < 0 ? -v : v, n = 0;
		while (a > 0) {
			a >>= 1;
			n++;
		}
		return n;
	}

	// the AAN forward DCT of 8 values at o, step s, in place (scaled: the divisors undo it)
	static function dct(d:Vector<Float>, o:Int, s:Int) {
		var d0 = d[o], d1 = d[o + s], d2 = d[o + 2 * s], d3 = d[o + 3 * s], d4 = d[o + 4 * s], d5 = d[o + 5 * s], d6 = d[o + 6 * s], d7 = d[o + 7 * s];
		var tmp0 = d0 + d7, tmp7 = d0 - d7, tmp1 = d1 + d6, tmp6 = d1 - d6, tmp2 = d2 + d5, tmp5 = d2 - d5, tmp3 = d3 + d4, tmp4 = d3 - d4;
		var tmp10 = tmp0 + tmp3, tmp13 = tmp0 - tmp3, tmp11 = tmp1 + tmp2, tmp12 = tmp1 - tmp2;
		d0 = tmp10 + tmp11;
		d4 = tmp10 - tmp11;
		var z1 = (tmp12 + tmp13) * 0.707106781;
		d2 = tmp13 + z1;
		d6 = tmp13 - z1;
		tmp10 = tmp4 + tmp5;
		tmp11 = tmp5 + tmp6;
		tmp12 = tmp6 + tmp7;
		var z5 = (tmp10 - tmp12) * 0.382683433;
		var z2 = tmp10 * 0.541196100 + z5;
		var z4 = tmp12 * 1.306562965 + z5;
		var z3 = tmp11 * 0.707106781;
		var z11 = tmp7 + z3, z13 = tmp7 - z3;
		d5 = z13 + z2;
		d3 = z13 - z2;
		d1 = z11 + z4;
		d7 = z11 - z4;
		d[o] = d0;
		d[o + s] = d1;
		d[o + 2 * s] = d2;
		d[o + 3 * s] = d3;
		d[o + 4 * s] = d4;
		d[o + 5 * s] = d5;
		d[o + 6 * s] = d6;
		d[o + 7 * s] = d7;
	}
}
