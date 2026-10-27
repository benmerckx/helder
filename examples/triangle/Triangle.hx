// title: Triangle
// summary: A coloured triangle: a vertex buffer, a pipeline and shaders written in Haxe, compiled to WGSL, GLSL, MSL and HLSL
// tags: gfx, shaders
// demo: canvas 512x384
import helder.gfx.*;
import helder.gfx.shader.ShaderMath.*;
import helder.os.*;

// A coloured triangle in a window (close it, or press Escape):
//
//   haxe -cp src -cp examples -main Triangle
//     --custom-target hxmc=triangle -D hxmc.libc=glibc
//
// (macOS and Windows: without -D hxmc.libc=glibc; the browser: -D
// hxmc.target=wasm32-wasi, run by src/helder/os/browser.mjs with the packages'
// imports.mjs, as on the site's examples page.) The shaders are Haxe (TriangleShader.hx),
// compiled by the shader macro into the target's shader languages. The
// tests (tests/gfx) draw the same frames headless and in a window
// (Xvfb on Linux, a canvas in headless Chromium).
class Triangle {
	final device:Device;
	final vertices:Buffer;
	final pipeline:Pipeline;
	final pass:PassDesc = {colors: [{load: Clear, clear: new Color(0.1, 0.1, 0.12)}]};

	public function new(device:Device) {
		this.device = device;
		var bytes = TriangleShader.vertexBytes([
			{pos: vec2(0, 0.6), color: vec3(1, 0, 0)},
			{pos: vec2(-0.6, -0.5), color: vec3(0, 1, 0)},
			{pos: vec2(0.6, -0.5), color: vec3(0, 0, 1)}
		]);
		vertices = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
		pipeline = device.createPipeline(TriangleShader.pipeline({topology: Triangles}));
	}

	// records the frame's pass; the caller ends the frame
	public function draw(enc:Encoder) {
		enc.beginPass(pass);
		enc.setPipeline(pipeline);
		enc.setVertexBuffer(0, vertices);
		enc.draw(3);
		enc.endPass();
	}

	public function frame() {
		var enc = device.beginFrame();
		if (enc == null) return;
		draw(enc);
		device.endFrame();
	}

	static function main() {
		var window = new Window("Triangle", 640, 480);
		var triangle = new Triangle(Device.create(window.surface));
		App.run(triangle.frame, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case _:
		});
	}
}
