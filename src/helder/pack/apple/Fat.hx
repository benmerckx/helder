package helder.pack.apple;

import haxe.io.Bytes;

// A universal binary (lipo's "fat" Mach-O): the header (big-endian: the
// magic, the slices' count), each slice's CPU type and subtype (read from
// its own Mach-O header), offset, size and alignment, then the slices,
// each at a multiple of its alignment (2^14: arm64's pages; x86-64's 2^12).
class Fat {
	public static function make(slices:Array<Bytes>):Bytes {
		var n = slices.length, header = 8 + 20 * n;
		var offsets = [], at = header;
		for (s in slices) {
			var align = alignOf(s);
			at = (at + (1 << align) - 1) & ~((1 << align) - 1);
			offsets.push(at);
			at += s.length;
		}
		var out = Bytes.alloc(at);
		inline function be(p:Int, v:Int) {
			out.set(p, v >>> 24);
			out.set(p + 1, (v >> 16) & 255);
			out.set(p + 2, (v >> 8) & 255);
			out.set(p + 3, v & 255);
		}
		be(0, 0xCAFEBABE);
		be(4, n);
		for (i in 0...n) {
			var s = slices[i], o = 8 + 20 * i;
			be(o, s.getInt32(4));
			be(o + 4, s.getInt32(8) & 0x00FFFFFF);
			be(o + 8, offsets[i]);
			be(o + 12, s.length);
			be(o + 16, alignOf(s));
			out.blit(offsets[i], s, 0, s.length);
		}
		return out;
	}

	// (CPU_TYPE_ARM64 0x0100000C: 2^14; the others 2^12)
	static function alignOf(s:Bytes):Int
		return s.getInt32(4) == 0x0100000C ? 14 : 12;
}
