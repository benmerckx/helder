package hxmc.gfx;

enum abstract Backend(Int) {
	// OpenGL ES 3.0 through EGL (Linux)
	var GL;
	// Metal (macOS)
	var Metal;
}
