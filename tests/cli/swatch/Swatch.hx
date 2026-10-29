import helder.asset.Asset;
import helder.async.Async;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import helder.view.graph.Read;

// A console program for the dev loop with assets (the cli lane natively,
// the asset-web lane in Chromium): an image and a text, loaded by path
// (helder.asset); under helder dev a change to either file is sent to it
// and loaded again behind the same handle, without a build: the image
// swapped in place (the same Image object, its size and pixels new), the
// text's reader (an effect reading value) run again. A line when one
// changes, looked at ten times a second on helder.async's loop (the
// page's, on the web).
class Swatch {
	static function main() {
		var image = Asset.image("swatch.png"), note = Asset.bytes("note.txt");
		var first:Null<helder.image.Image> = null, version = -1;
		// (the effect waits for the note: its compute reads it, pending until it is here)
		root(_ -> effect(() -> note.read(), (b:haxe.io.Bytes) -> Sys.println("note: " + StringTools.trim(b.toString()))));
		Async.main(_ -> while (alive()) {
			var img = image.peek();
			if (img != null && img.version != version) {
				if (first == null) first = img;
				version = img.version;
				var px = [for (i in 0...4) StringTools.hex(img.pixels.get(i), 2)].join("").toLowerCase();
				Sys.println('swatch: ${img.width}x${img.height} px $px version $version' + (img == first ? " same image" : " another image"));
			}
			#if hxmc.dev
			helder.dev.Hot.framed();
			#end
			Async.delay(0.1);
		});
	}

	// (the dev server's messages: false once this build handed over)
	static function alive():Bool {
		#if hxmc.dev
		return helder.dev.Hot.poll();
		#else
		return true;
		#end
	}
}
