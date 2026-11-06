package helder.canvas.web;

import haxe.io.Bytes;
import hxmc.unsafe.Callback;

// Images decoded by the browser (createImageBitmap) in a web build, kept in
// the page as a handle (WebImage) that WebCanvas.drawHandle draws: helder's
// own decoders are not needed, so -dce leaves them out of a build that only
// decodes this way. Decoding is the browser's and asynchronous; a wasm call
// cannot wait for it, so the work is split as a page or a frame splits it:
// a prepare step starts the decodes (decode, or all for several), returns,
// and done is called back once they have arrived (from the page's event
// loop: the program keeps running after main returns), when the drawing,
// synchronous, can use them. width x height: decoded near that size (the
// size it is drawn at; the browser's resize), 0 for its own. EXIF's
// orientation is not applied (a PDF's image is drawn as stored). What the
// browser cannot decode arrives as null: the caller's own decoder then.
class BrowserImages {
	static final waiting = new Map<Int, Null<WebImage>->Void>();
	static var next = 1;

	public static function decode(bytes:Bytes, type:String, width:Int, height:Int, done:Null<WebImage>->Void) {
		var t = next++;
		waiting.set(t, done);
		var mime = Bytes.ofString(type);
		WebCanvas.WebCanvasImports.canvas_decode(hxmc.unsafe.BytesPtr.of(bytes, 0, bytes.length), bytes.length, hxmc.unsafe.BytesPtr.of(mime, 0, mime.length), mime.length,
			width, height, t, Callback.addr(arrived));
	}

	// several at once: done with each one's image (null where it failed), in order; at once when none
	public static function all(requests:Array<{bytes:Bytes, type:String, width:Int, height:Int}>, done:Array<Null<WebImage>>->Void) {
		var out:Array<Null<WebImage>> = [for (_ in requests) null], left = requests.length;
		if (left == 0) {
			done(out);
			return;
		}
		for (i in 0...requests.length) {
			var r = requests[i];
			decode(r.bytes, r.type, r.width, r.height, img -> {
				out[i] = img;
				if (--left == 0) done(out);
			});
		}
	}

	@:hxmc.callback static function arrived(ticket:Int, handle:Int, width:Int, height:Int):Int {
		var f = waiting.get(ticket);
		waiting.remove(ticket);
		if (f != null) f(handle == 0 ? null : new WebImage(handle, width, height));
		Sys.stdout().flush();
		return 0;
	}
}

// an image the page holds: its handle, its size as decoded
class WebImage extends helder.canvas.HandleImages.ImageHandle {
	var released = false;

	public function new(handle, width, height)
		super(handle, width, height);

	// the page lets go of it (an ImageBitmap closed)
	public function release() {
		if (released) return;
		released = true;
		WebCanvas.WebCanvasImports.canvas_release(handle);
	}
}
