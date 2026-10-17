package hxmc.gfx;

// The formats every back end has (GL ES 3.0, Metal, D3D11, WebGPU). Each
// can be sampled and be a pass's target (TextureDesc.renderTarget; GL:
// RGBA16F and R32F need EXT_color_buffer_float, which Mesa, ANGLE and
// Android's drivers have; WebGL2 enables it). R32F and the depth formats
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

	inline function get_depth():Bool
		return this >= (cast Depth16 : Int);

	inline function get_filterable():Bool
		return this < (cast R32F : Int);
}
