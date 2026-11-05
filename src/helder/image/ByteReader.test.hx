package helder.image;

import haxe.io.Bytes;
import helder.test.Test;

// ByteReader's own checks, now its in-range reads are unchecked
// (Bytes.fastGet): every read past the bytes it was given, before them, or
// whose position and length overflow an Int, an ImageError (Corrupt),
// never a byte of what lies beyond; reads within them as Bytes' own.
function tests() {
	describe("ByteReader", () -> {
		// (a segment of a larger buffer: the reader sees its 8 bytes only)
		var whole = Bytes.ofHex("00112233445566778899aabbccddeeff");
		var seg = whole.sub(4, 8);
		var r = new ByteReader(seg);
		test("reads within the bytes", () -> {
			equals(r.u8(0), 0x44);
			equals(r.u8(7), 0xbb);
			equals(r.be16(0), 0x4455);
			equals(r.le32(4), 0xbbaa9988);
			equals(r.u8or0(8), 0);
			equals(r.string(0, 2).length, 2);
		});
		test("a read past the end, before the start or overflowing: refused", () -> {
			var before = ByteReader.refused;
			for (f in [
				() -> r.u8(8),
				() -> r.u8(-1),
				() -> r.u8(0x7FFFFFFF),
				() -> r.be16(7),
				() -> r.be32(5),
				() -> r.le24(6),
				() -> r.sub(4, 5).length,
				() -> r.sub(0x7FFFFFFF, 2).length,
				() -> r.string(-1, 2).length,
				() -> {
					r.blitTo(Bytes.alloc(16), 0, 1, 8);
					0;
				},
				() -> {
					r.addTo(new haxe.io.BytesBuffer(), 6, 0x7FFFFFFF);
					0;
				}
			])
				equals(outcome(f), "corrupt");
			equals(ByteReader.refused - before, 11);
			assert(!r.has(0x7FFFFFFF, 2));
			assert(!r.has(4, -1));
			assert(r.has(0, 8));
			assert(!r.has(1, 8));
		});
	});
}

private function outcome(f:() -> Int):String {
	try {
		f();
		return "ok";
	} catch (e:ImageError) {
		return Std.string(e.kind);
	}
}
