package helder.pack;

import haxe.io.Bytes;

// A growable little-endian byte buffer, for the formats the packagers write
// (zip, binary XML, DEX, the APK's signing block). Ported from hxmc
// (hxmc.Buf), MIT.
class Buf {
	public var b:Bytes;
	public var len:Int = 0;

	public function new(cap = 256) {
		b = Bytes.alloc(cap < 16 ? 16 : cap);
	}

	inline function need(n:Int) {
		if (len + n > b.length) grow(len + n);
	}

	function grow(min:Int) {
		var cap = b.length * 2;
		while (cap < min)
			cap *= 2;
		var nb = Bytes.alloc(cap);
		nb.blit(0, b, 0, len);
		b = nb;
	}

	public inline function u8(v:Int) {
		need(1);
		b.set(len++, v);
	}

	public inline function u16(v:Int) {
		need(2);
		b.set(len, v);
		b.set(len + 1, v >> 8);
		len += 2;
	}

	public inline function u32(v:Int) {
		need(4);
		b.set(len, v);
		b.set(len + 1, v >> 8);
		b.set(len + 2, v >> 16);
		b.set(len + 3, v >>> 24);
		len += 4;
	}

	// a 64-bit value from its halves
	public inline function u64(lo:Int, hi:Int) {
		u32(lo);
		u32(hi);
	}

	public function bytes(src:Bytes, pos = 0, n = -1) {
		if (n < 0) n = src.length - pos;
		need(n);
		b.blit(len, src, pos, n);
		len += n;
	}

	public function buf(src:Buf) {
		need(src.len);
		b.blit(len, src.b, 0, src.len);
		len += src.len;
	}

	public function str(s:String)
		bytes(Bytes.ofString(s));

	// unsigned LEB128 (DEX's)
	public function uleb(v:Int) {
		while (true) {
			var c = v & 0x7f;
			v >>>= 7;
			if (v == 0) {
				u8(c);
				return;
			}
			u8(c | 0x80);
		}
	}

	public function zeros(n:Int) {
		need(n);
		b.fill(len, n, 0);
		len += n;
	}

	public function align(a:Int, fill = 0) {
		while (len % a != 0)
			u8(fill);
	}

	public function toBytes():Bytes
		return b.sub(0, len);
}
