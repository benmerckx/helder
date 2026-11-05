package helder.image;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.test.Test;

// Exif: the orientation from a JPEG's APP1 and a WebP's EXIF chunk, both
// byte orders; offsets out of the block, a loop of IFDs, a count past the
// end, another type: 1; the eight orientations applied to a 3x2 image
function tests() {
	describe("Exif", () -> {
		test("a JPEG's APP1, little- and big-endian", () -> {
			for (o in 1...9) {
				equals(Exif.orientation(jpeg(tiff(true, o))), o);
				equals(Exif.orientation(jpeg(tiff(false, o))), o);
			}
		});
		test("a WebP's EXIF chunk, with and without Exif's prefix", () -> {
			equals(Exif.orientation(webp(tiff(true, 6), false)), 6);
			equals(Exif.orientation(webp(tiff(false, 8), true)), 8);
		});
		test("hostile blocks: 1", () -> {
			// IFD0 past the block, before the header, at itself (a loop of next IFDs)
			for (off in [0x7FFFFFF0, 0xFFFFFFF8, 4, 100000]) {
				var t = tiff(true, 6);
				t.setInt32(4, off);
				equals(Exif.orientation(jpeg(t)), 1, 'offset $off');
			}
			var loop = tiff(true, 1);
			// (the next IFD's offset is IFD0's own: never followed)
			loop.setInt32(8 + 2 + 12, 8);
			equals(Exif.orientation(jpeg(loop)), 1);
			// a count past the end
			var many = tiff(true, 6);
			many.setUInt16(8, 0xFFFF);
			many.setUInt16(10, 0x0100);
			equals(Exif.orientation(jpeg(many)), 1);
			// a LONG, a value outside 1-8, not TIFF
			var long = tiff(true, 6);
			long.setUInt16(12, 4);
			equals(Exif.orientation(jpeg(long)), 1);
			equals(Exif.orientation(jpeg(tiff(true, 9))), 1);
			equals(Exif.orientation(jpeg(Bytes.ofString("not a tiff block"))), 1);
			// cut anywhere
			var file = jpeg(tiff(false, 6));
			for (n in 0...file.length)
				assert(Exif.orientation(file.sub(0, n)) >= 1);
			equals(Exif.orientation(Bytes.ofString("GIF89a")), 1);
		});
		test("the eight orientations applied", () -> {
			// a b c / d e f
			var src = Bytes.alloc(24);
			for (i in 0...6)
				src.setInt32(4 * i, "abcdef".charCodeAt(i));
			var want = ["", "abc/def", "cba/fed", "fed/cba", "def/abc", "ad/be/cf", "da/eb/fc", "fc/eb/da", "cf/be/ad"];
			for (o in 1...9) {
				var r = Exif.apply(src, 3, 2, o);
				var rows = [for (y in 0...r.height) [for (x in 0...r.width) String.fromCharCode(r.rgba.getInt32(4 * (y * r.width + x)))].join("")];
				equals(rows.join("/"), want[o], 'orientation $o');
				equals(Exif.swaps(o), o >= 5);
			}
		});
		test("JpegDecoder applies it", () -> {
			// (a 16x8 baseline JPEG turned by an APP1 of orientation 6: 8x16)
			var plain = sys.io.File.getBytes("tests/image/jpeg/large-420.jpg");
			var d = JpegDecoder.decode(plain);
			var b = new BytesBuffer();
			b.add(plain.sub(0, 2));
			b.add(app1(tiff(true, 6)));
			b.add(plain.sub(2, plain.length - 2));
			var turned = JpegDecoder.decode(b.getBytes());
			equals([turned.width, turned.height], [d.height, d.width]);
			equals(Image.size(b.getBytes()), {width: d.height, height: d.width});
		});
	});
}

// (a TIFF block: its header, IFD0 of one entry, the orientation a SHORT)
private function tiff(le:Bool, o:Int):Bytes {
	var b = Bytes.alloc(8 + 2 + 12 + 4);
	inline function w16(p:Int, v:Int)
		if (le) {
			b.set(p, v & 255);
			b.set(p + 1, v >> 8);
		} else {
			b.set(p, v >> 8);
			b.set(p + 1, v & 255);
		}
	inline function w32(p:Int, v:Int)
		if (le) {
			w16(p, v & 0xFFFF);
			w16(p + 2, v >>> 16);
		} else {
			w16(p, v >>> 16);
			w16(p + 2, v & 0xFFFF);
		}
	b.set(0, le ? 0x49 : 0x4D);
	b.set(1, le ? 0x49 : 0x4D);
	w16(2, 42);
	w32(4, 8);
	w16(8, 1);
	w16(10, 0x112);
	w16(12, 3);
	w32(14, 1);
	w16(18, o);
	return b;
}

private function app1(t:Bytes):Bytes {
	var b = new BytesBuffer(), n = 2 + 6 + t.length;
	b.addByte(0xFF);
	b.addByte(0xE1);
	b.addByte(n >> 8);
	b.addByte(n & 255);
	b.addString("Exif");
	b.addByte(0);
	b.addByte(0);
	b.add(t);
	return b.getBytes();
}

private function jpeg(t:Bytes):Bytes {
	var b = new BytesBuffer();
	b.addByte(0xFF);
	b.addByte(0xD8);
	b.add(app1(t));
	b.add(Bytes.ofHex("ffd9"));
	return b.getBytes();
}

private function webp(t:Bytes, prefix:Bool):Bytes {
	var body = new BytesBuffer();
	if (prefix) body.add(Bytes.ofHex("457869660000"));
	body.add(t);
	var data = body.getBytes(), b = new BytesBuffer(), n = Bytes.alloc(4);
	b.addString("RIFF");
	n.setInt32(0, 4 + 18 + 8 + data.length + (data.length & 1));
	b.add(n);
	b.addString("WEBP");
	b.addString("VP8X");
	var x = Bytes.alloc(4 + 10);
	x.setInt32(0, 10);
	x.set(4, 0x08);
	b.add(x);
	b.addString("EXIF");
	var m = Bytes.alloc(4);
	m.setInt32(0, data.length);
	b.add(m);
	b.add(data);
	if (data.length & 1 == 1) b.addByte(0);
	return b.getBytes();
}
