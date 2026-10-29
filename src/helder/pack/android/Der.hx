package helder.pack.android;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

// The ASN.1 DER the APK's signature needs (Apk, P256): the debug key's
// self-signed X.509 certificate, its SubjectPublicKeyInfo, ECDSA signatures.
// Ported from hxmc (hxmc.android.Der), MIT.
class Der {
	public static function tlv(tag:Int, content:Bytes):Bytes {
		var b = new BytesBuffer();
		b.addByte(tag);
		var n = content.length;
		if (n < 0x80) b.addByte(n) else {
			var len = [];
			while (n > 0) {
				len.unshift(n & 0xff);
				n >>= 8;
			}
			b.addByte(0x80 | len.length);
			for (x in len)
				b.addByte(x);
		}
		b.add(content);
		return b.getBytes();
	}

	static function cat(parts:Array<Bytes>):Bytes {
		var b = new BytesBuffer();
		for (p in parts)
			b.add(p);
		return b.getBytes();
	}

	public static function seq(parts:Array<Bytes>):Bytes
		return tlv(0x30, cat(parts));

	public static function set(parts:Array<Bytes>):Bytes
		return tlv(0x31, cat(parts));

	// an unsigned big-endian number as an INTEGER (no leading zeros, a 0 before a high bit)
	public static function integer(v:Bytes):Bytes {
		var i = 0;
		while (i < v.length - 1 && v.get(i) == 0)
			i++;
		var b = new BytesBuffer();
		if (v.get(i) & 0x80 != 0) b.addByte(0);
		b.addBytes(v, i, v.length - i);
		return tlv(0x02, b.getBytes());
	}

	public static function small(v:Int):Bytes
		return integer(Bytes.ofHex(StringTools.hex(v, 8)));

	// a dotted object identifier
	public static function oid(dotted:String):Bytes {
		var p = dotted.split(".").map(Std.parseInt);
		var b = new BytesBuffer();
		b.addByte(40 * p[0] + p[1]);
		for (k in 2...p.length) {
			var v = p[k], parts = [v & 0x7f];
			v >>>= 7;
			while (v > 0) {
				parts.unshift(0x80 | (v & 0x7f));
				v >>>= 7;
			}
			for (x in parts)
				b.addByte(x);
		}
		return tlv(0x06, b.getBytes());
	}

	public static function bitString(v:Bytes):Bytes
		return tlv(0x03, cat([Bytes.ofHex("00"), v]));

	public static function utf8(s:String):Bytes
		return tlv(0x0c, Bytes.ofString(s));

	public static function printable(s:String):Bytes
		return tlv(0x13, Bytes.ofString(s));

	// UTCTime before 2050, GeneralizedTime from then (RFC 5280)
	public static function time(d:Date):Bytes {
		var y = d.getUTCFullYear();
		function two(v:Int)
			return StringTools.lpad(Std.string(v), "0", 2);
		var rest = two(d.getUTCMonth() + 1) + two(d.getUTCDate()) + two(d.getUTCHours()) + two(d.getUTCMinutes()) + two(d.getUTCSeconds()) + "Z";
		return y < 2050 ? tlv(0x17, Bytes.ofString(two(y % 100) + rest)) : tlv(0x18, Bytes.ofString(Std.string(y) + rest));
	}

	public static function explicit(n:Int, content:Bytes):Bytes
		return tlv(0xa0 | n, content);

	// ---- reading back (the checks): a TLV's tag, where it starts (at), its
	// content (start until end)

	public static function read(b:Bytes, at:Int):DerNode {
		var tag = b.get(at), n = b.get(at + 1), start = at + 2;
		if (n & 0x80 != 0) {
			var k = n & 0x7f;
			n = 0;
			for (i in 0...k)
				n = (n << 8) | b.get(at + 2 + i);
			start += k;
		}
		if (start + n > b.length) throw "DER: a length past the end at " + at;
		return {tag: tag, at: at, start: start, end: start + n};
	}

	// the TLVs in a constructed one's content
	public static function children(b:Bytes, node:DerNode):Array<DerNode> {
		var out = [], at = node.start;
		while (at < node.end) {
			var c = read(b, at);
			out.push(c);
			at = c.end;
		}
		return out;
	}
}

typedef DerNode = {tag:Int, at:Int, start:Int, end:Int};
