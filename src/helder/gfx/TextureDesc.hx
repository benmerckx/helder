package helder.gfx;

// A 2D texture, its rows top to bottom: the first row of data is v = 0
// (helder.gfx.shader.Texture2D), on every back end, a render target's too.
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
	// samples a pixel: 1 (the default), or 4 for a multisampled render target
	// or depth texture (RGBA8, RGBA8Srgb, RGBA16F or a depth format; one mip
	// level, no data): drawn into by pipelines of 4 samples
	// (PipelineDesc.samples), never sampled; a pass's colour resolved into a
	// single-sampled texture at its end (ColorTarget.resolve)
	?samples:Int,
	// the first level's texels (width * height * format.texelSize bytes)
	?data:haxe.io.Bytes
}
