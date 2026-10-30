package helder.gfx;

import helder.image.Image;

// An image's texture (helder.image's Image), its pixels dropped after
// (Image.uploaded: unless it retains them, decoded again from its file
// when read): a browser image (Image.decodeInBrowser's) copied from the
// browser's decoded pixels, never through the module's memory; any other
// uploaded from its pixels, premultiplied first when asked. The renderers'
// one way to upload an Image (helder.ui's, the sprites', a program's).
//
//   var t = ImageTexture.create(device, img, {premultiply: true});
class ImageTexture {
	// format: RGBA8 (default) or RGBA8Srgb; mips: every level (generated
	// from the first)
	public static function create(device:Device, img:Image, ?options:{?premultiply:Bool, ?format:TextureFormat, ?mips:Bool}):Texture {
		var pre = options != null && options.premultiply == true, mips = options != null && options.mips == true;
		var format:TextureFormat = options != null && options.format != null ? options.format : RGBA8;
		var t:Null<Texture> = null;
		if (img.browser != 0 && !img.hasPixels && device.decodesImages && img.browserPremultiplied == pre) {
			t = device.createTexture({width: img.width, height: img.height, format: format, mipLevels: mips ? 0 : 1});
			device.writeTextureImage(t, img.browser);
		} else if (pre) {
			img.premultiplied(p -> t = device.createTexture({width: img.width, height: img.height, format: format, data: p, mipLevels: mips ? 0 : 1}));
		} else
			t = device.createTexture({width: img.width, height: img.height, format: format, data: img.pixels, mipLevels: mips ? 0 : 1});
		if (mips && !(img.browser != 0 && !img.hasPixels)) device.generateMips(t);
		img.uploaded();
		return t;
	}

	// an encoded image's texture (PNG, JPEG, WebP, GIF: length bytes of b at
	// offset) decoded by the browser, null where it is not one (not in a
	// browser, or a header it does not read): blank until the browser has
	// decoded it (a frame or a few), its levels then generated (mips)
	public static function decoded(device:Device, b:haxe.io.Bytes, offset = 0, length = -1, ?format:TextureFormat, mips = false):Null<Texture> {
		#if (hxmc.target == "wasm32-wasi")
		if (!device.decodesImages) return null;
		if (length < 0) length = b.length - offset;
		var size = Image.size(b, offset, length);
		if (size == null) return null;
		var t = device.createTexture({width: size.width, height: size.height, format: format == null ? RGBA8 : format, mipLevels: mips ? 0 : 1});
		device.writeTextureImage(t, start(b, offset, length), true);
		return t;
		#else
		return null;
		#end
	}

	#if (hxmc.target == "wasm32-wasi")
	@:hxmc.unsafe static function start(b:haxe.io.Bytes, offset:Int, length:Int):Int
		return helder.image.WebImages.decode(0, hxmc.unsafe.BytesPtr.of(b, offset, length), length, 0);
	#end
}
