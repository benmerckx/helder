package helder.os;

// text/uri-list (RFC 2483), as X11's drags carry files: one URI a line
// (CRLF, or LF alone), # a comment; the file: URIs' paths, percent-decoded
// as UTF-8 (file:///a%20b, file://host/a b: /a b); other schemes left out
class UriList {
	public static function paths(text:String):Array<String> {
		var out = [];
		for (raw in text.split("\n")) {
			var line = StringTools.trim(raw);
			if (line == "" || line.charAt(0) == "#" || !StringTools.startsWith(line.toLowerCase(), "file:")) continue;
			var rest = line.substr(5);
			// (file://host/path: the authority dropped; file:/path as it is)
			if (StringTools.startsWith(rest, "//")) {
				var slash = rest.indexOf("/", 2);
				if (slash < 0) continue;
				rest = rest.substr(slash);
			}
			var path = decode(rest);
			if (path != null && path != "") out.push(path);
		}
		return out;
	}

	// (%XX as bytes, then the bytes as UTF-8; a broken escape: null)
	static function decode(s:String):Null<String> {
		var b = new haxe.io.BytesBuffer(), raw = haxe.io.Bytes.ofString(s), i = 0;
		while (i < raw.length) {
			var c = raw.get(i);
			if (c != "%".code) {
				b.addByte(c);
				i++;
				continue;
			}
			if (i + 2 >= raw.length) return null;
			var hi = hex(raw.get(i + 1)), lo = hex(raw.get(i + 2));
			if (hi < 0 || lo < 0) return null;
			b.addByte(hi * 16 + lo);
			i += 3;
		}
		return b.getBytes().toString();
	}

	static function hex(c:Int):Int
		return c >= "0".code && c <= "9".code ? c - "0".code : c >= "a".code && c <= "f".code ? c - "a".code + 10 : c >= "A".code && c <= "F".code ? c - "A".code + 10 : -1;
}
