package helder.pack;

import haxe.io.Bytes;

// Zip archives as the packagers write them (an APK: helder.pack.android.Apk;
// an .ipa: helder.pack.ios.Bundle), and read back (the checks, helder dev's
// library out of an APK). Ported from hxmc (hxmc.Zip), MIT.
class Zip {
	// stored entries, each one's data at a multiple of its alignment (over
	// 1: the local header's extra field padded, Android's alignment field
	// 0xd935, as zipalign -P 16 and apksigner write it), with a Unix mode
	// when it has one (an .ipa's executable: 0755); a fixed date
	// (1981-01-01): the same input gives the same bytes
	public static function stored(entries:Array<ZipEntry>):Bytes {
		var out = new Buf(1 << 20), cd = new Buf(4096);
		inline function dosTime(b:Buf) {
			b.u16(0); // 00:00:00
			b.u16((1 << 9) | (1 << 5) | 1); // 1981-01-01 (1980 + 1)
		}
		for (e in entries) {
			var at = out.len, name = Bytes.ofString(e.name);
			var crc = haxe.crypto.Crc32.make(e.data);
			// the data's offset: header (30) + name + extra (4 + 2 + padding)
			var aligned = e.align > 1;
			var extra = aligned ? 6 : 0, dataAt = at + 30 + name.length + extra;
			var pad = aligned ? (e.align - (dataAt % e.align)) % e.align : 0;
			extra += pad;
			out.u32(0x04034b50);
			out.u16(10); // version needed
			out.u16(0x0800); // flags: UTF-8 names
			out.u16(0); // stored
			dosTime(out);
			out.u32(crc);
			out.u32(e.data.length);
			out.u32(e.data.length);
			out.u16(name.length);
			out.u16(extra);
			out.bytes(name);
			if (aligned) {
				out.u16(0xd935);
				out.u16(extra - 4);
				out.u16(e.align);
				out.zeros(pad);
			}
			out.bytes(e.data);
			cd.u32(0x02014b50);
			cd.u16(e.mode != null ? 0x30a : 10); // version made by (3: Unix, with a mode)
			cd.u16(10);
			cd.u16(0x0800);
			cd.u16(0);
			dosTime(cd);
			cd.u32(crc);
			cd.u32(e.data.length);
			cd.u32(e.data.length);
			cd.u16(name.length);
			cd.u16(0); // extra
			cd.u16(0); // comment
			cd.u16(0); // disk
			cd.u16(0); // internal attributes
			cd.u32(e.mode != null ? (0x8000 | e.mode) << 16 : 0); // external attributes (S_IFREG | mode)
			cd.u32(at);
			cd.bytes(name);
		}
		var cdAt = out.len;
		out.buf(cd);
		out.u32(0x06054b50);
		out.u16(0);
		out.u16(0);
		out.u16(entries.length);
		out.u16(entries.length);
		out.u32(cd.len);
		out.u32(cdAt);
		out.u16(0);
		return out.toBytes();
	}

	// the entries of an archive (its central directory, from the end of
	// central directory: the last 22 bytes, or before a comment), each with
	// its data (stored, or deflated: inflated), where that data starts, its
	// Unix mode (null without one), CRC-32 checked
	public static function read(b:Bytes):Array<ZipRead> {
		var eocd = b.length - 22;
		while (eocd >= 0 && b.getInt32(eocd) != 0x06054b50)
			eocd--;
		if (eocd < 0) throw "not a zip archive: no end of central directory";
		var n = b.getUInt16(eocd + 10), at = b.getInt32(eocd + 16);
		var out = [];
		for (_ in 0...n) {
			if (b.getInt32(at) != 0x02014b50) throw "a broken central directory at " + at;
			var made = b.getUInt16(at + 4), method = b.getUInt16(at + 10), crc = b.getInt32(at + 16), size = b.getInt32(at + 20),
				full = b.getInt32(at + 24), nl = b.getUInt16(at + 28), xl = b.getUInt16(at + 30), cl = b.getUInt16(at + 32),
				attrs = b.getInt32(at + 38), local = b.getInt32(at + 42);
			var name = b.getString(at + 46, nl);
			if (b.getInt32(local) != 0x04034b50) throw name + ": no local header";
			var dataAt = local + 30 + b.getUInt16(local + 26) + b.getUInt16(local + 28);
			var data = switch method {
				case 0: b.sub(dataAt, size);
				case 8: inflate(b.sub(dataAt, size), full);
				case m: throw name + ": compression method " + m;
			}
			if (haxe.crypto.Crc32.make(data) != crc) throw name + ": its CRC-32 differs";
			out.push({
				name: name,
				data: data,
				method: method,
				dataAt: dataAt,
				mode: made >> 8 == 3 ? (attrs >>> 16) & 0xfff : null
			});
			at += 46 + nl + xl + cl;
		}
		return out;
	}

	// one entry's data, null when there is none of that name
	public static function entry(b:Bytes, name:String):Null<Bytes> {
		for (e in read(b))
			if (e.name == name) return e.data;
		return null;
	}

	static function inflate(raw:Bytes, size:Int):Bytes {
		var out = Bytes.alloc(size);
		var n = new haxe.zip.InflateImpl(new haxe.io.BytesInput(raw), false, false).readBytes(out, 0, size);
		if (n != size) throw "a deflated entry shorter than its size";
		return out;
	}
}

typedef ZipEntry = {name:String, data:Bytes, align:Int, ?mode:Int};
typedef ZipRead = {name:String, data:Bytes, method:Int, dataAt:Int, mode:Null<Int>};
