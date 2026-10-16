package hxmc.gfx;

// how a texture is sampled between texels (one level: no mipmaps); the
// edges are clamped
enum abstract Filter(Int) {
	var Linear;
	var Nearest;
}
