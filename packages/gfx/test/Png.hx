import haxe.io.Bytes;

// 8-bit RGB PNG files for the tests: written with stored (uncompressed)
// deflate blocks, read with any compression and filters (haxe.zip.InflateImpl).
class Png {
	// rgba: width * height * 4 bytes, rows top to bottom; alpha is dropped
	public static function encode(rgba:Bytes, width:Int, height:Int):Bytes {
		var raw = new haxe.io.BytesBuffer();
		for (y in 0...height) {
			raw.addByte(0);
			for (x in 0...width) {
				var p = 4 * (y * width + x);
				raw.addByte(rgba.get(p));
				raw.addByte(rgba.get(p + 1));
				raw.addByte(rgba.get(p + 2));
			}
		}
		var data = raw.getBytes();
		var z = new haxe.io.BytesOutput();
		z.bigEndian = true;
		z.writeByte(0x78);
		z.writeByte(0x01);
		// (blocks of 16 KB: haxe.zip.InflateImpl's window takes at most 32 KB of a stored block at once)
		var pos = 0;
		while (true) {
			var n = data.length - pos > 16384 ? 16384 : data.length - pos;
			z.writeByte(pos + n == data.length ? 1 : 0);
			z.writeByte(n & 0xFF);
			z.writeByte(n >> 8);
			z.writeByte(~n & 0xFF);
			z.writeByte((~n >> 8) & 0xFF);
			z.writeFullBytes(data, pos, n);
			pos += n;
			if (pos == data.length) break;
		}
		z.writeInt32(haxe.crypto.Adler32.make(data));
		var o = new haxe.io.BytesOutput();
		o.bigEndian = true;
		for (b in [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
			o.writeByte(b);
		var ihdr = new haxe.io.BytesOutput();
		ihdr.bigEndian = true;
		ihdr.writeInt32(width);
		ihdr.writeInt32(height);
		for (b in [8, 2, 0, 0, 0])
			ihdr.writeByte(b);
		chunk(o, "IHDR", ihdr.getBytes());
		chunk(o, "IDAT", z.getBytes());
		chunk(o, "IEND", Bytes.alloc(0));
		return o.getBytes();
	}

	static function chunk(o:haxe.io.BytesOutput, type:String, data:Bytes) {
		o.writeInt32(data.length);
		var td = Bytes.alloc(4 + data.length);
		td.blit(0, Bytes.ofString(type), 0, 4);
		td.blit(4, data, 0, data.length);
		o.writeFullBytes(td, 0, td.length);
		o.writeInt32(haxe.crypto.Crc32.make(td));
	}

	// an 8-bit RGB or RGBA PNG (not interlaced) as RGBA, rows top to bottom
	public static function decode(png:Bytes):{width:Int, height:Int, rgba:Bytes} {
		var i = new haxe.io.BytesInput(png);
		i.bigEndian = true;
		i.position = 8;
		var width = 0, height = 0, channels = 3;
		var idat = new haxe.io.BytesBuffer();
		while (i.position < png.length) {
			var n = i.readInt32(), type = i.readString(4);
			var data = i.read(n);
			i.readInt32();
			switch type {
				case "IHDR":
					height = (data.get(4) << 24) | (data.get(5) << 16) | (data.get(6) << 8) | data.get(7);
					width = (data.get(0) << 24) | (data.get(1) << 16) | (data.get(2) << 8) | data.get(3);
					if (data.get(8) != 8 || data.get(12) != 0 || (data.get(9) != 2 && data.get(9) != 6)) throw "Png: 8-bit RGB or RGBA only";
					channels = data.get(9) == 6 ? 4 : 3;
				case "IDAT":
					idat.add(data);
				case _:
			}
		}
		var raw = haxe.zip.InflateImpl.run(new haxe.io.BytesInput(idat.getBytes()));
		var stride = width * channels;
		var out = Bytes.alloc(width * height * 4);
		var prev = Bytes.alloc(stride), cur = Bytes.alloc(stride);
		for (y in 0...height) {
			var f = raw.get(y * (stride + 1));
			for (x in 0...stride) {
				var v = raw.get(y * (stride + 1) + 1 + x);
				var a = x >= channels ? cur.get(x - channels) : 0, b = prev.get(x), c = x >= channels ? prev.get(x - channels) : 0;
				v += switch f {
					case 0: 0;
					case 1: a;
					case 2: b;
					case 3: (a + b) >> 1;
					case 4:
						var p = a + b - c, pa = abs(p - a), pb = abs(p - b), pc = abs(p - c);
						pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
					case _: throw "Png: filter " + f;
				}
				cur.set(x, v & 0xFF);
			}
			for (x in 0...width)
				for (k in 0...4)
					out.set(4 * (y * width + x) + k, k < channels ? cur.get(x * channels + k) : 255);
			var t = prev;
			prev = cur;
			cur = t;
		}
		return {width: width, height: height, rgba: out};
	}

	static inline function abs(v:Int)
		return v < 0 ? -v : v;
}
