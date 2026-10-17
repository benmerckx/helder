package hxmc.gfx;

// texture coordinates outside 0..1
enum abstract Wrap(Int) {
	var Repeat;
	var Clamp;
	var Mirror;
}
