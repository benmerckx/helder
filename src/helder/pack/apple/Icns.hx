package helder.pack.apple;

import haxe.io.Bytes;

// A macOS app icon file (.icns, CFBundleIconFile; for macOS bundles):
// "icns" and the file's length (big-endian), then entries, each a type,
// its length (with the 8 bytes of these two) and a PNG. The types by pixel
// size, 16 to 1024, the @2x ones (ic11 to ic14, ic10) included: what
// iconutil writes from an .iconset.
class Icns {
	public static final TYPES = [
		{type: "icp4", px: 16}, {type: "icp5", px: 32}, {type: "ic11", px: 32}, {type: "ic12", px: 64}, {type: "ic07", px: 128},
		{type: "ic13", px: 256}, {type: "ic08", px: 256}, {type: "ic14", px: 512}, {type: "ic09", px: 512}, {type: "ic10", px: 1024}
	];

	// png(px): the icon as a PNG of px x px
	public static function write(png:Int->Bytes):Bytes {
		var entries = [for (t in TYPES) {type: t.type, data: png(t.px)}];
		var b = new haxe.io.BytesBuffer();
		function be(v:Int) {
			b.addByte(v >>> 24);
			b.addByte((v >> 16) & 0xff);
			b.addByte((v >> 8) & 0xff);
			b.addByte(v & 0xff);
		}
		var total = 8;
		for (e in entries)
			total += 8 + e.data.length;
		b.addString("icns");
		be(total);
		for (e in entries) {
			b.addString(e.type);
			be(8 + e.data.length);
			b.add(e.data);
		}
		return b.getBytes();
	}
}
