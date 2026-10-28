package helder.asset;

import helder.image.Image;

// Asset.image's loader: a PNG decoded as a GC-free job (helder.image's
// ImageJobs: the file copied once from where the bundle has it into the
// job's buffer, the pixels the job's output), a JPEG, GIF or WebP on the
// loop's thread (Image.decode). A reload's image is put in the old one
// (Image.replace: its pixels and size; renderers upload it again).
class ImageAsset {
	@:helder.asset.load public static function load(key:String, ?file:String):Asset<Image>
		return Assets.handle("image", key, _ -> decode(key, file), (old, fresh) -> {
			old.replace(fresh);
			old;
		});

	@:coroutine static function decode(key:String, file:Null<String>):Image {
		#if (target.name == "hxmc")
		var b = Files.readBuffer(key, file);
		if (b.length >= 8 && b.get(0) == 0x89 && b.get(1) == 0x50 && b.get(2) == 0x4E && b.get(3) == 0x47) {
			var p = helder.image.ImageJobs.pixels(b);
			return new Image(p.width, p.height, p.rgba.view());
		}
		var bytes = haxe.io.Bytes.alloc(b.length);
		b.blitToBytes(0, bytes, 0, b.length);
		b.free();
		return Image.decode(bytes);
		#else
		return Image.decode(Files.read(key, file));
		#end
	}
}
