package helder.pack;

import haxe.io.Bytes;

// Deflate's raw stream (RFC 1951) and gzip's file (RFC 1952) for the
// desktop releases' archives (Zip's deflated entries, Tar's .tar.gz):
// helder.image.PngEncoder's compressor (LZ77 by a hash of three bytes, a
// short chain, the fixed Huffman codes) without its zlib wrapper. Pure Haxe:
// no zlib; written once by a build, so a smaller ratio than zlib -9's is
// the price.
class Deflate {
	// the raw deflate stream
	public static function raw(data:Bytes):Bytes {
		var z = helder.image.PngEncoder.zlib(data);
		// (zlib's: two bytes of header, the stream, four of Adler-32)
		return z.sub(2, z.length - 6);
	}

	// a .gz file of data (no name, no time: the same input gives the same bytes)
	public static function gzip(data:Bytes):Bytes {
		var body = raw(data);
		var out = new Buf(body.length + 18);
		out.u8(0x1f);
		out.u8(0x8b);
		out.u8(8); // deflate
		out.u8(0); // flags
		out.u32(0); // mtime
		out.u8(0); // extra flags
		out.u8(3); // Unix
		out.bytes(body);
		out.u32(haxe.crypto.Crc32.make(data));
		out.u32(data.length);
		return out.toBytes();
	}
}
