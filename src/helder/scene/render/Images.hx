package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.Device;
import helder.gfx.Texture;
import helder.image.JpegDecoder;
import helder.image.PngDecoder;
import helder.image.WebpDecoder;

// Models' images made textures (GltfScene, PackedModel, Environment):
// decoded by the decoder the program gives, mime type and bytes to RGBA8
// pixels, rows top to bottom, or null for a format it does not read;
// helder.image's by name (png, common), or a program's own:
//   Images.decode = Images.png;
// Without one, textures are left out (materials keep their factors), and
// no decoder is linked (a glTF viewer natively: 805 KB, 1.1 MB with
// common's three).
class Images {
	public static var decode(default, set):Null<(String, Bytes) -> Null<{width:Int, height:Int, rgba:Bytes}>>;

	// helder.image's PNG decoder, for PNG images only
	public static function png(mime:String, bytes:Bytes):Null<{width:Int, height:Int, rgba:Bytes}>
		return mime == "image/png" ? PngDecoder.decode(bytes) : null;

	// helder.image's PNG, JPEG and WebP decoders (glTF's image/png and
	// image/jpeg, EXT_texture_webp's image/webp)
	public static function common(mime:String, bytes:Bytes):Null<{width:Int, height:Int, rgba:Bytes}>
		return switch mime {
			case "image/png": PngDecoder.decode(bytes);
			case "image/jpeg": JpegDecoder.decode(bytes);
			case "image/webp": WebpDecoder.decode(bytes);
			case _: null;
		}

	// (made when a decoder is given: without one, no texture making, mip
	// levels included, is linked)
	static var make:Null<(Device, String, Bytes) -> Null<Texture>>;

	static function set_decode(f) {
		make = f != null ? made : null;
		return decode = f;
	}

	// an encoded image's texture, mip-mapped (mipmapped; sRGB colours:
	// decoded by the shader); null without a decoder or for a format it does not read
	public static function texture(device:Device, mime:String, bytes:Null<Bytes>):Null<Texture>
		return make != null && bytes != null ? make(device, mime, bytes) : null;

	static function made(device:Device, mime:String, bytes:Bytes):Null<Texture> {
		// (in a browser, with Image.decodeInBrowser: the browser's decoder, its
		// pixels never in the module's memory, the mips the GPU's; blank for
		// the frames until it is decoded)
		if (helder.image.Image.decodeInBrowser) {
			var t = helder.gfx.ImageTexture.decoded(device, bytes, 0, -1, null, true);
			if (t != null) return t;
		}
		var image = decode(mime, bytes);
		if (image == null) return null;
		return mipmapped(device, image.width, image.height, image.rgba);
	}

	// an RGBA8 image's texture with its mip levels made here (2x2 boxes,
	// down to 1x1): the same texels on every GPU, whose own mip making
	// differs, and an environment's small levels are its light
	public static function mipmapped(device:Device, width:Int, height:Int, rgba:Bytes):Texture {
		var t = device.createTexture({width: width, height: height, data: rgba, mipLevels: 0});
		var w = width, h = height, level = 0, src = rgba;
		while (w > 1 || h > 1) {
			var nw = w > 1 ? w >> 1 : 1, nh = h > 1 ? h >> 1 : 1;
			var dst = Bytes.alloc(nw * nh * 4);
			for (y in 0...nh)
				for (x in 0...nw) {
					var x0 = w > 1 ? 2 * x : 0, y0 = h > 1 ? 2 * y : 0, x1 = w > 1 ? x0 + 1 : x0, y1 = h > 1 ? y0 + 1 : y0;
					for (c in 0...4) {
						var sum = src.get(4 * (y0 * w + x0) + c) + src.get(4 * (y0 * w + x1) + c) + src.get(4 * (y1 * w + x0) + c) + src.get(4 * (y1 * w + x1) + c);
						dst.set(4 * (y * nw + x) + c, (sum + 2) >> 2);
					}
				}
			level++;
			device.writeTexture(t, dst, 0, 0, nw, nh, 0, level);
			w = nw;
			h = nh;
			src = dst;
		}
		return t;
	}

}
