package helder.pdf;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.pdf.PdfValue;
import helder.pdf.Document;

// A stream's filters undone, in order: FlateDecode (haxe.zip's inflate,
// PNG and TIFF predictors after), LZWDecode (its EarlyChange, predictors),
// ASCIIHexDecode, ASCII85Decode, RunLengthDecode, CCITTFaxDecode (Ccitt);
// DCTDecode left to the image reader (helder.image's JPEG decoder), as
// are the image filters helder does not decode (JPXDecode, JBIG2Decode:
// an Unsupported error). Each output is bounded by budget (PdfLimits'
// maxStream, and what the document has left of maxDecoded): a zip bomb
// stops at it.
class Filters {
	// the bytes through the filters; stopAt: the first filter left for the caller (DCTDecode), its bytes as they are then
	public static function decode(data:Bytes, dict:PdfDict, budget:Int, ?doc:Document, ?stopAt:Array<String>):{data:Bytes, rest:Null<String>, parms:Null<PdfDict>} {
		var filters = list(dict.get("Filter"), doc), parms = list(dict.has("DecodeParms") ? dict.get("DecodeParms") : dict.get("DP"), doc);
		for (i in 0...filters.length) {
			var f = Values.name(filters[i], "");
			var p = i < parms.length ? Values.dict(doc != null ? doc.resolve(parms[i]) : parms[i]) : null;
			if (stopAt != null && stopAt.indexOf(f) >= 0) return {data: data, rest: f, parms: p};
			data = switch f {
				case "FlateDecode" | "Fl": predict(inflate(data, budget), p, budget);
				case "LZWDecode" | "LZW": predict(lzw(data, p == null ? 1 : Values.int(p.get("EarlyChange"), 1), budget), p, budget);
				case "ASCIIHexDecode" | "AHx": asciiHex(data);
				case "ASCII85Decode" | "A85": ascii85(data);
				case "RunLengthDecode" | "RL": runLength(data, budget);
				case "CCITTFaxDecode" | "CCF": Ccitt.decode(data, p, budget) ?? throw PdfError.corrupt("CCITT fax data");
				case "Crypt": data;
				case _: throw PdfError.unsupported("the " + f + " filter");
			}
		}
		return {data: data, rest: null, parms: null};
	}

	static function list(v:PdfValue, doc:Null<Document>):Array<PdfValue> {
		if (doc != null) v = doc.resolve(v);
		return switch v {
			case PNull: [];
			case PArray(a): a;
			case _: [v];
		}
	}

	public static function inflate(data:Bytes, budget:Int):Bytes {
		var input = new haxe.io.BytesInput(data);
		var out = new BytesBuffer(), chunk = Bytes.alloc(65536), total = 0;
		try {
			// (a zlib header, or none: raw deflate as some writers make it)
			var raw = data.length < 2 || ((data.get(0) & 15) != 8 || (((data.get(0) << 8) | data.get(1)) % 31) != 0);
			var z = new haxe.zip.InflateImpl(input, !raw, !raw);
			while (true) {
				var n = z.readBytes(chunk, 0, chunk.length);
				if (n <= 0) break;
				total += n;
				if (total > budget) throw PdfError.tooLarge("a stream past " + budget + " bytes decoded");
				out.addBytes(chunk, 0, n);
			}
		} catch (e:PdfError) {
			throw e;
		} catch (e:Dynamic) {
			// (a stream cut short or damaged: what came of it, as viewers show it)
		}
		return out.getBytes();
	}

	// PNG's predictors (10 to 15: each row's own) and TIFF's (2)
	static function predict(data:Bytes, p:Null<PdfDict>, budget:Int):Bytes {
		if (p == null) return data;
		var pred = Values.int(p.get("Predictor"), 1);
		if (pred <= 1) return data;
		var colors = Values.int(p.get("Colors"), 1), bpc = Values.int(p.get("BitsPerComponent"), 8), cols = Values.int(p.get("Columns"), 1);
		if (colors < 1 || colors > 32 || cols < 1 || cols > 1 << 24 || (bpc != 1 && bpc != 2 && bpc != 4 && bpc != 8 && bpc != 16))
			throw PdfError.corrupt("a predictor's parameters");
		var bpp = Std.int(Math.max(1, Math.ceil(colors * bpc / 8))), row = Std.int(Math.ceil(colors * bpc * cols / 8));
		if (pred == 2) {
			if (bpc != 8) return data;
			var out = data.sub(0, data.length);
			var r = 0;
			while (r + row <= out.length) {
				for (i in bpp...row)
					out.set(r + i, (out.get(r + i) + out.get(r + i - bpp)) & 255);
				r += row;
			}
			return out;
		}
		var rows = Std.int(data.length / (row + 1));
		var out = Bytes.alloc(rows * row), prev = Bytes.alloc(row);
		for (y in 0...rows) {
			var f = data.get(y * (row + 1)), s = y * (row + 1) + 1, o = y * row;
			for (i in 0...row) {
				var x = data.get(s + i), a = i >= bpp ? out.get(o + i - bpp) : 0, b = prev.get(i), c = i >= bpp ? prev.get(i - bpp) : 0;
				var v = switch f {
					case 1: x + a;
					case 2: x + b;
					case 3: x + ((a + b) >> 1);
					case 4:
						var pp = a + b - c, pa = Std.int(Math.abs(pp - a)), pb = Std.int(Math.abs(pp - b)), pc = Std.int(Math.abs(pp - c));
						x + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c);
					case _: x;
				}
				out.set(o + i, v & 255);
			}
			prev = out.sub(o, row);
		}
		return out;
	}

	static function lzw(data:Bytes, early:Int, budget:Int):Bytes {
		var out = new BytesBuffer(), total = 0;
		var dict:Array<Bytes> = [], next = 258, width = 9, prev:Null<Bytes> = null;
		inline function reset() {
			dict = [for (i in 0...256) Bytes.ofHex(StringTools.hex(i, 2))];
			dict.push(null);
			dict.push(null);
			next = 258;
			width = 9;
			prev = null;
		}
		reset();
		var bit = 0, len = data.length * 8;
		while (bit + width <= len) {
			var code = 0;
			for (k in 0...width) {
				var p = bit + k;
				code = (code << 1) | ((data.get(p >> 3) >> (7 - (p & 7))) & 1);
			}
			bit += width;
			if (code == 256) {
				reset();
				continue;
			}
			if (code == 257) break;
			var entry:Bytes;
			if (code < next && dict[code] != null) entry = dict[code] else if (prev != null && code == next) {
				var b = new BytesBuffer();
				b.add(prev);
				b.addByte(prev.get(0));
				entry = b.getBytes();
			} else
				break;
			total += entry.length;
			if (total > budget) throw PdfError.tooLarge("an LZW stream past " + budget + " bytes");
			out.add(entry);
			if (prev != null && next < 4096) {
				var b = new BytesBuffer();
				b.add(prev);
				b.addByte(entry.get(0));
				dict[next++] = b.getBytes();
			}
			prev = entry;
			if (next + early >= (1 << width) && width < 12) width++;
		}
		return out.getBytes();
	}

	static function asciiHex(data:Bytes):Bytes {
		var out = new BytesBuffer(), hi = -1;
		for (i in 0...data.length) {
			var c = data.get(i);
			if (c == ">".code) break;
			var v = c >= "0".code && c <= "9".code ? c - "0".code : c >= "a".code && c <= "f".code ? c - 87 : c >= "A".code && c <= "F".code ? c - 55 : -1;
			if (v < 0) continue;
			if (hi < 0) hi = v else {
				out.addByte(hi * 16 + v);
				hi = -1;
			}
		}
		if (hi >= 0) out.addByte(hi * 16);
		return out.getBytes();
	}

	static function ascii85(data:Bytes):Bytes {
		// (a group's digits so far as its value, in a float: 85^5 is past 2^32)
		var out = Bytes.alloc(Std.int(data.length / 5 * 4) + 4), len = 0, count = 0, v = 0.0, i = 0;
		inline function put(n:Int, k:Int) {
			if (len + 4 > out.length) {
				var grown = Bytes.alloc(out.length * 2 + 4);
				grown.blit(0, out, 0, len);
				out = grown;
			}
			for (j in 0...k)
				out.set(len + j, (n >>> (24 - 8 * j)) & 255);
			len += k;
		}
		if (data.length >= 2 && data.get(0) == "<".code && data.get(1) == "~".code) i = 2;
		while (i < data.length) {
			var c = data.get(i++);
			if (c == "~".code) break;
			if (Parser.isWhite(c)) continue;
			if (c == "z".code && count == 0) {
				put(0, 4);
				continue;
			}
			if (c < 33 || c > 117) continue;
			v = v * 85 + (c - 33);
			if (++count == 5) {
				put(Std.int(v % 4294967296.0), 4);
				v = 0;
				count = 0;
			}
		}
		if (count > 1) {
			var k = count;
			while (count < 5) {
				v = v * 85 + 84;
				count++;
			}
			put(Std.int(v % 4294967296.0), k - 1);
		}
		return out.sub(0, len);
	}

	static function runLength(data:Bytes, budget:Int):Bytes {
		var out = new BytesBuffer(), i = 0, total = 0;
		while (i < data.length) {
			var n = data.get(i++);
			if (n == 128) break;
			if (n < 128) {
				var k = Std.int(Math.min(n + 1, data.length - i));
				out.addBytes(data, i, k);
				i += k;
				total += k;
			} else if (i < data.length) {
				var v = data.get(i++);
				for (_ in 0...257 - n)
					out.addByte(v);
				total += 257 - n;
			}
			if (total > budget) throw PdfError.tooLarge("a RunLength stream past " + budget + " bytes");
		}
		return out.getBytes();
	}
}
