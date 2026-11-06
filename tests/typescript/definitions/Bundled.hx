import helder.asset.Asset;
import helder.async.Async;

// Asset's definitions in Haxe: bundled.ts prints the same.
class Bundled {
	static function main()
		Async.main(_ -> {
			var data = Asset.bytes("files/note.txt").load();
			Sys.println('${data.length} ${data.getString(0, 7)}');
			var a = Asset.image("files/pixels.png"), b = Asset.image("files/pixels.png");
			a.load();
			b.load();
			Sys.println('${a.ready} ${b.ready}');
		});
}
