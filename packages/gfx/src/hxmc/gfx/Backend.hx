package hxmc.gfx;

enum abstract Backend(Int) {
	// OpenGL ES 3.0 through EGL (Linux)
	var GL;
	// Metal (macOS)
	var Metal;
	// Direct3D 11 (Windows)
	var D3D11;
	// WebGPU (the browser, WebAssembly)
	var WebGPU;
}
