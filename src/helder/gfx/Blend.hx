package helder.gfx;

// How a pipeline's colour combines with the target's (src: the fragment's
// colour, a its alpha; dst: the target's)
enum abstract Blend(Int) {
	// src
	var Opaque;
	// src * a + dst * (1 - a); the target's alpha a + dst.a * (1 - a)
	var Alpha;
	// src * a + dst; the target's alpha a + dst.a
	var Additive;
	// src + dst * (1 - a): colours already multiplied by their alpha
	var Premultiplied;
}
