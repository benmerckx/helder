package hxmc.scene.render;

import haxe.io.Bytes;
import hxmc.gfx.Device;
import hxmc.gfx.Texture;

// Models' images made textures (GltfScene, PackedModel): decoded by the
// decoder the program gives (no decoder is linked unless named): mime
// type and bytes to RGBA8 pixels, rows top to bottom, or null for a format
// it does not read. @hxmc/ui's:
//   Images.decode = (mime, b) -> mime == "image/jpeg" ? hxmc.ui.JpegDecoder.decode(b) : hxmc.ui.PngDecoder.decode(b);
// Without one, textures are left out (materials keep their factors).
class Images {
	public static var decode(default, set):Null<(String, Bytes) -> Null<{width:Int, height:Int, rgba:Bytes}>>;

	// (made when a decoder is given: without one, no texture making, mip
	// levels included, is linked)
	static var make:Null<(Device, String, Bytes) -> Null<Texture>>;

	static function set_decode(f) {
		make = f != null ? made : null;
		return decode = f;
	}

	// an encoded image's texture, mip-mapped (sRGB colours: decoded by the
	// shader); null without a decoder or for a format it does not read
	public static function texture(device:Device, mime:String, bytes:Null<Bytes>):Null<Texture>
		return make != null && bytes != null ? make(device, mime, bytes) : null;

	static function made(device:Device, mime:String, bytes:Bytes):Null<Texture> {
		var image = decode(mime, bytes);
		if (image == null) return null;
		var t = device.createTexture({width: image.width, height: image.height, data: image.rgba, mipLevels: 0});
		device.generateMips(t);
		return t;
	}
}
