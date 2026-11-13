package helder.asset;

import helder.image.Image;

// Asset.image's loader: a PNG decoded as a GC-free job (helder.image's
// ImageJobs: the file copied once from where the bundle has it into the
// job's buffer, the pixels the job's output), a JPEG, GIF or WebP on the
// loop's thread (Image.decode). A reload's image is put in the old one
// (Image.replace: its pixels and size; renderers upload it again).
class ImageAsset {
	public static function load(key:String, ?file:String):Asset<Image>
		return Assets.handle("image", key, _ -> decode(key, file), (old, fresh) -> {
			old.replace(fresh);
			old;
		});

	@:coroutine static function decode(key:String, file:Null<String>):Image {
		#if (hxmc.target == "wasm32-wasi")
		// (decoded by the browser, uploaded from there: Image.decodeInBrowser)
		if (Image.decodeInBrowser && file == null) return browser(key);
		#end
		#if (target.name == "hxmc")
		var b = Files.readBuffer(key, file);
		if (b.length >= 8 && b.get(0) == 0x89 && b.get(1) == 0x50 && b.get(2) == 0x4E && b.get(3) == 0x47) {
			var p = helder.image.ImageJobs.pixels(b);
			return new Image(p.width, p.height, helder.image.ImageJobs.keep(p.rgba));
		}
		var bytes = b.getBytes(0, b.length);
		b.close();
		return Image.decode(bytes);
		#else
		return Image.decode(Files.read(key, file));
		#end
	}

	#if (hxmc.target == "wasm32-wasi")
	// the file fetched and decoded in the browser, premultiplied (what ui's
	// and the sprites' textures are)
	// (decode's file when it decodes a fetch's body: none)
	static final NONE = haxe.io.Bytes.alloc(0);

	@:coroutine static function browser(key:String):Image {
		var f = helder.async.Fetch.fetched(AssetPath.url(AssetPath.bundled(key)), (loaded, total) -> Assets.progressed(key, loaded, total));
		var n = helder.async.Web.fetch_length(f);
		var h = helder.image.WebImages.decode(f, hxmc.ReadOnlySpan.ofBytes(NONE), 0, 1);
		Assets.progressed(key, n, n);
		var state = helder.async.Async.suspendCancellable(cont -> {
			var done = false;
			helder.async.Async.loopOf(cont.context).check(() -> {
				if (done) return true;
				var s = helder.image.WebImages.state(h);
				if (s == 0) return false;
				done = true;
				cont.resume(s, null);
				return true;
			});
			return _ -> done = true;
		});
		if (state != 1) {
			helder.image.WebImages.free(h);
			throw new haxe.Exception('$key: not an image the browser decodes');
		}
		if (Image.browserImages == null) Image.browserImages = {file: file, close: h -> helder.image.WebImages.close(h)};
		return Image.ofBrowser(h, helder.image.WebImages.width(h), helder.image.WebImages.height(h), true);
	}

	static function file(h:Int):haxe.io.Bytes {
		var n = helder.image.WebImages.file_length(h), b = haxe.io.Bytes.alloc(n);
		helder.image.WebImages.file_take(h, hxmc.Span.ofBytes(b));
		return b;
	}
	#end
}
