package hxmc.gfx;

// A pipeline's colour blending (the colour target's alpha too: one-minus-
// source-alpha, so that a target stays opaque)
enum abstract Blend(Int) {
	// the fragment's colour replaces the target's
	var Replace;
	// straight alpha: src * a + dst * (1 - a)
	var Alpha;
	// premultiplied alpha: src + dst * (1 - a)
	var Premultiplied;
	// src + dst
	var Add;
}
