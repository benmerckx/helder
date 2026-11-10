package helder.gfx;

// How a pipeline's colour combines with the target's (src: the fragment's
// colour, a its alpha; dst: the target's)
enum abstract Blend(Int) {
	// src
	var Opaque;
	// src * a + dst * (1 - a); the target's alpha a + dst.a * (1 - a)
	var Alpha;
	// src + dst, alpha ignored (Unreal's Additive, Bevy's AlphaMode::Add):
	// light added, fading it the shader's to do (src * a: three.js' and
	// Godot's); the target's alpha a + dst.a
	var Additive;
	// src + dst * (1 - a): colours already multiplied by their alpha
	var Premultiplied;
	// dst * src: what is behind tinted (glass's colour); the target's alpha kept
	var Multiply;
}
