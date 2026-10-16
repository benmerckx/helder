package hxmc.gfx;

enum abstract TextureFormat(Int) {
	// one 8-bit channel, sampled as (r, 0, 0, 1): masks, glyph coverage
	var R8;
	// four 8-bit channels
	var RGBA8;

	public var bytesPerPixel(get, never):Int;

	inline function get_bytesPerPixel():Int
		return this == 0 ? 1 : 4;
}
