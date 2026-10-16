package hxmc.gfx;

// A 2D texture of one mip level, its rows top to bottom: the first row of
// data is v = 0 (hxmc.gfx.shader.Texture2D), on every back end.
typedef TextureDesc = {
	width:Int,
	height:Int,
	?format:TextureFormat,
	// the initial texels (width * height * 4 bytes for RGBA8)
	?data:haxe.io.Bytes
}
