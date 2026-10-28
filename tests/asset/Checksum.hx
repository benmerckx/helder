import helder.asset.Asset;
import helder.async.Async;

// Assets read where each build put them (the asset lane, the pack lane;
// CI's emulator and simulator jobs: tests/pack/android.sh, ios.sh): a
// line per file with its size and CRC-32, an image's size and its pixels'
// CRC-32, then the bundle's list. The executable's data on desktop, the
// APK's assets/, the app's, beside the page; files/dropped.txt only in
// code nothing runs, so in no bundle.
//   helder build tests/asset/Checksum.hx [--target ...]
class Checksum {
	static function main() {
		#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		helder.os.android.Activity.activity;
		#end
		Async.main(_ -> {
			for (a in [Asset.bytes("files/kept.txt"), Asset.bytes("files/pixels.png")]) {
				var b = a.load();
				Sys.println('asset: ${a.key} ${b.length} bytes, crc ${hex(haxe.crypto.Crc32.make(b))}');
			}
			var img = Asset.image("files/pixels.png").load();
			Sys.println('asset: files/pixels.png ${img.width}x${img.height}, pixels crc ${hex(haxe.crypto.Crc32.make(img.pixels))}');
			Sys.println("asset: bundled " + helder.asset.Assets.bundled().join(","));
		});
	}

	static function hex(v:Int):String
		return StringTools.hex(v, 8).toLowerCase();

	// (never called)
	static function unused()
		return Asset.bytes("files/dropped.txt");
}
