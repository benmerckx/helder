package helder.gfx;

// The formats every back end has (GL ES 3.0, Metal, D3D11, WebGPU). Each
// can be sampled and be a pass's target (TextureDesc.renderTarget; GL:
// RGBA16F and R32F need EXT_color_buffer_float, which Mesa, ANGLE and
// most Android drivers have, or for RGBA16F EXT_color_buffer_half_float;
// WebGL2 enables either; without them a pass into one throws, which
// helder.scene's <Scene> takes as its cue to draw in 8 bits). R32F and the depth formats
// are not filterable everywhere (GL ES, WebGPU): they are read through a
// sampler of Nearest filters, and have no generated mip levels. Data
// (TextureDesc.data, Device.writeTexture) is texelSize bytes a texel, its
// channels in order.
enum abstract TextureFormat(Int) {
	// 4 bytes a texel (red, green, blue, alpha), each read as 0..1
	var RGBA8;
	// RGBA8 stored in sRGB: read as linear values (decoded), written encoded
	var RGBA8Srgb;
	// 1 byte (red; green and blue read as 0, alpha as 1)
	var R8;
	// 2 bytes (red, green)
	var RG8;
	// 8 bytes: 4 half floats (IEEE 754 binary16, little-endian)
	var RGBA16F;
	// 4 bytes: a float (red)
	var R32F;
	// depth targets (no data: written by passes), read as red 0..1
	var Depth16;
	var Depth32F;
	// compressed, 4x4 blocks (Device.supports: not every GPU has them;
	// sampled only, written a whole level at a time, no generated mips, a
	// width and height of multiples of 4): BC1 (8 bytes a block, RGB, opaque:
	// desktops), BC3 (16: BC1's colours and an alpha block), ASTC 4x4 (16:
	// phones, Apple's GPUs); read as linear values (helder.image's
	// BlockCompress makes them)
	var BC1;
	var BC3;
	var ASTC4x4;

	public var texelSize(get, never):Int;
	public var depth(get, never):Bool;
	public var filterable(get, never):Bool;

	inline function get_texelSize():Int
		return switch (cast this : TextureFormat) {
			case R8: 1;
			case RG8 | Depth16: 2;
			case RGBA16F: 8;
			case _: 4;
		}

	public var compressed(get, never):Bool;

	// the bytes of a level of width x height texels (a compressed format's:
	// its blocks', the last row's and column's whole)
	public inline function levelBytes(width:Int, height:Int):Int
		return compressed ? ((width + 3) >> 2) * ((height + 3) >> 2) * blockBytes : width * height * texelSize;

	// a compressed format's bytes for a 4x4 block
	public var blockBytes(get, never):Int;

	inline function get_blockBytes():Int
		return (cast this : TextureFormat) == BC1 ? 8 : 16;

	inline function get_compressed():Bool
		return this >= (cast BC1 : Int);

	inline function get_depth():Bool
		return this == (cast Depth16 : Int) || this == (cast Depth32F : Int);

	inline function get_filterable():Bool
		return this < (cast R32F : Int) || compressed;
}
