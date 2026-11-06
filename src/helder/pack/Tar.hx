package helder.pack;

import haxe.io.Bytes;

// A tar archive (POSIX ustar) as a Linux release ships it (helder.cli.Desktop:
// the .tar.gz): regular files with their Unix modes, directories, and
// symbolic links; root's owner, a fixed time, so that the same input gives
// the same bytes. A name past ustar's 100 bytes is split at a slash into
// its prefix (155) and name.
class Tar {
	public static function write(entries:Array<TarEntry>):Bytes {
		var out = new Buf(1 << 20);
		for (e in entries) {
			var kind = e.link != null ? "2".code : e.data == null ? "5".code : "0".code;
			var name = kind == "5".code && !StringTools.endsWith(e.name, "/") ? e.name + "/" : e.name;
			var prefix = "";
			if (Bytes.ofString(name).length > 100) {
				var cut = name.lastIndexOf("/", name.length - 2);
				while (cut > 0 && Bytes.ofString(name.substr(cut + 1)).length > 100)
					cut = name.lastIndexOf("/", cut - 1);
				if (cut <= 0 || Bytes.ofString(name.substr(0, cut)).length > 155) throw 'Tar: $name: too long a name';
				prefix = name.substr(0, cut);
				name = name.substr(cut + 1);
			}
			var size = e.data == null ? 0 : e.data.length;
			var h = Bytes.alloc(512);
			h.fill(0, 512, 0);
			function str(at:Int, s:String, max:Int) {
				var b = Bytes.ofString(s);
				h.blit(at, b, 0, b.length < max ? b.length : max);
			}
			// (an octal number in width - 1 digits and a NUL)
			function oct(at:Int, v:Int, width:Int) {
				var s = "", n = v;
				while (n > 0) {
					s = Std.string(n & 7) + s;
					n >>>= 3;
				}
				str(at, StringTools.lpad(s, "0", width - 1), width - 1);
			}
			str(0, name, 100);
			oct(100, e.mode ?? (kind == "0".code ? 0x1a4 : 0x1ed), 8);
			oct(108, 0, 8);
			oct(116, 0, 8);
			oct(124, size, 12);
			oct(136, 1, 12); // (1970-01-01 00:00:01: a fixed time)
			h.set(156, kind);
			if (e.link != null) str(157, e.link, 100);
			str(257, "ustar", 6);
			str(263, "00", 2);
			str(265, "root", 32);
			str(297, "root", 32);
			str(345, prefix, 155);
			// (the checksum: the header's bytes, the field itself as spaces)
			for (i in 148...156)
				h.set(i, " ".code);
			var sum = 0;
			for (i in 0...512)
				sum += h.get(i);
			oct(148, sum, 7);
			h.set(155, " ".code);
			out.bytes(h);
			if (e.data != null) {
				out.bytes(e.data);
				for (_ in 0...(512 - size % 512) % 512)
					out.u8(0);
			}
		}
		for (_ in 0...1024)
			out.u8(0);
		return out.toBytes();
	}

	// the archive gzipped (Deflate.gzip)
	public static function gz(entries:Array<TarEntry>):Bytes
		return Deflate.gzip(write(entries));
}

// a file (data), a directory (neither data nor link), or a symbolic link (link: its target)
typedef TarEntry = {name:String, ?data:Bytes, ?mode:Int, ?link:String};
