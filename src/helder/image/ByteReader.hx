package helder.image;

import haxe.io.Bytes;

// A file's bytes as the decoders read them: every read checked against the
// file's end (natively a Bytes' read past it is not: hxmc leaves it
// unspecified, as Haxe does), one past it refused as an ImageError
// (Corrupt, "a read past the end"). The decoders read their input through
// nothing else (tests/image/unsafe.mjs checks it); what they made
// themselves (their planes, canvases, tables) they read as Bytes. u8or0 is
// for the formats that show what came of a file cut short (GIF's): zeros
// past the end, on purpose. refused counts the reads refused (the fuzz
// lane checks each surfaced as an ImageError).
final class ByteReader {
	public final bytes:Bytes;
	public final length:Int;

	public static var refused = 0;

	public inline function new(bytes:Bytes) {
		this.bytes = bytes;
		this.length = bytes.length;
	}

	// (p within [0, length): one unsigned comparison)
	public inline function has(p:Int, n = 1):Bool
		return n >= 0 && p >= 0 && p <= length - n;

	public inline function u8(p:Int):Int
		return p >= 0 && p < length ? bytes.get(p) : refuse(p, 1);

	public inline function u8or0(p:Int):Int
		return p >= 0 && p < length ? bytes.get(p) : 0;

	public inline function be16(p:Int):Int
		return (u8(p) << 8) | u8(p + 1);

	public inline function le16(p:Int):Int
		return u8(p) | (u8(p + 1) << 8);

	public inline function le24(p:Int):Int
		return u8(p) | (u8(p + 1) << 8) | (u8(p + 2) << 16);

	public inline function be32(p:Int):Int
		return (u8(p) << 24) | (u8(p + 1) << 16) | (u8(p + 2) << 8) | u8(p + 3);

	public inline function le32(p:Int):Int
		return u8(p) | (u8(p + 1) << 8) | (u8(p + 2) << 16) | (u8(p + 3) << 24);

	public function string(p:Int, n:Int):String {
		if (!has(p, n)) refuse(p, n);
		return bytes.getString(p, n);
	}

	// n bytes at p, copied
	public function sub(p:Int, n:Int):Bytes {
		if (!has(p, n)) refuse(p, n);
		return bytes.sub(p, n);
	}

	// n bytes at p into a buffer (BytesBuffer.addBytes, checked first)
	public function addTo(b:haxe.io.BytesBuffer, p:Int, n:Int) {
		if (!has(p, n)) refuse(p, n);
		b.addBytes(bytes, p, n);
	}

	// n bytes at p into out at o
	public function blitTo(out:Bytes, o:Int, p:Int, n:Int) {
		if (!has(p, n)) refuse(p, n);
		out.blit(o, bytes, p, n);
	}

	static function refuse(p:Int, n:Int):Int {
		refused++;
		throw ImageError.corrupt('a read past the end (${n} at $p)');
	}
}
