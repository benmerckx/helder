import js.lib.DataView;
import js.lib.Uint8Array;
import js.html.TextDecoder;

typedef Entry = {path:String, data:Uint8Array};

// A pack: a little-endian u32 n, n bytes of JSON [[path, size], ...], then
// the files' bytes in that order (Build writes them: std.pack, src.pack,
// rt/<target>.pack)
class Pack {
	public static function unpack(b:Uint8Array):Array<Entry> {
		var n = new DataView(b.buffer, b.byteOffset).getUint32(0, true);
		var index:Array<Array<Dynamic>> = haxe.Json.parse(new TextDecoder().decode(b.subarray(4, 4 + n)));
		var at = 4 + n;
		return [
			for (e in index) {
				var size:Int = e[1];
				var entry = {path: (e[0] : String), data: b.subarray(at, at + size)};
				at += size;
				entry;
			}
		];
	}
}
