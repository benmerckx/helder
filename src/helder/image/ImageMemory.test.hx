package helder.image;

import helder.test.Test;

// ImageMemory: a decode's planes and pixels off the heap give the same
// pixels as on it (JPEG, its EXIF turn too; lossy WebP; PNG), the result
// taken, the rest freed
@:hxmc.unsafe(gc) function tests() {
	describe("ImageMemory", () -> {
		for (f in ["jpeg/large-420.jpg", "jpeg/orient6.jpg", "jpeg/progressive-420.jpg", "webp/lossy-alpha.webp", "png/rgb8.png"])
			test('off the heap: $f as on it', () -> {
				var file = sys.io.File.getBytes("tests/image/" + f);
				var on = Image.decode(file).pixels;
				var mem = ImageMemory.offHeapMemory();
				var d = StringTools.endsWith(f, ".jpg") ? JpegDecoder.decode(file, mem) : StringTools.endsWith(f, ".webp") ? WebpDecoder.decode(file, mem) : PngDecoder.decode(file, mem);
				equals(d.rgba.toHex(), on.toHex());
				#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
				var b = mem.take(d.rgba);
				mem.free();
				equals(b.getBytes(0, b.length).toHex(), on.toHex());
				b.free();
				#end
			});
	});
}
