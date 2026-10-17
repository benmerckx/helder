package hxmc.gfx;

// A 2D texture, its rows top to bottom: the first row of data is v = 0
// (hxmc.gfx.shader.Texture2D), on every back end, a render target's too.
typedef TextureDesc = {
	width:Int,
	height:Int,
	// default RGBA8
	?format:TextureFormat,
	// mip levels, each half the size of the one before (default 1; 0: all of
	// them, down to 1x1); filled by Device.writeTexture or generateMips
	?mipLevels:Int,
	// a pass's colour or depth target (ColorTarget.texture,
	// DepthTarget.texture) that shaders then sample; its contents come from
	// passes and generateMips, not data (depth formats are always targets)
	?renderTarget:Bool,
	// the first level's texels (width * height * format.texelSize bytes)
	?data:haxe.io.Bytes
}
