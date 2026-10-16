import hxmc.gfx.*;
import hxmc.os.*;

// A coloured triangle in a window (close it, or press Escape):
//
//   haxe -cp packages/os/src -cp packages/gfx/src -cp packages/gfx/examples -main Triangle
//     --custom-target hxmc=triangle -D hxmc.libc=glibc
//
// (macOS: without -D hxmc.libc=glibc.) The tests (packages/gfx/test) draw the
// same frames headless and in a window (Xvfb on Linux).
class Triangle {
	static final VERTEX = "#version 300 es
layout(location = 0) in vec2 pos;
layout(location = 1) in vec3 color;
out vec3 vColor;
void main() {
	vColor = color;
	gl_Position = vec4(pos, 0.0, 1.0);
}
";
	static final FRAGMENT = "#version 300 es
precision mediump float;
in vec3 vColor;
out vec4 fragColor;
void main() {
	fragColor = vec4(vColor, 1.0);
}
";
	// (Metal: until the shader macro writes both)
	static final VERTEX_MSL = "#include <metal_stdlib>
using namespace metal;
struct In { float2 pos [[attribute(0)]]; float3 color [[attribute(1)]]; };
struct Out { float4 position [[position]]; float3 color; };
vertex Out main0(In v [[stage_in]]) {
	Out o;
	o.position = float4(v.pos, 0.0, 1.0);
	o.color = v.color;
	return o;
}
";
	static final FRAGMENT_MSL = "#include <metal_stdlib>
using namespace metal;
struct In { float4 position [[position]]; float3 color; };
fragment float4 main0(In v [[stage_in]]) {
	return float4(v.color, 1.0);
}
";

	final device:Device;
	final vertices:Buffer;
	final pipeline:Pipeline;
	final pass:PassDesc = {colors: [{load: Clear, clear: new Color(0.1, 0.1, 0.12)}]};

	public function new(device:Device) {
		this.device = device;
		// x, y, r, g, b
		var data = [0.0, 0.6, 1, 0, 0, -0.6, -0.5, 0, 1, 0, 0.6, -0.5, 0, 0, 1];
		var bytes = haxe.io.Bytes.alloc(4 * data.length);
		for (i in 0...data.length)
			bytes.setFloat(4 * i, data[i]);
		vertices = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
		pipeline = device.createPipeline({
			vertex: device.createShader({stage: Vertex, code: {glsl: VERTEX, msl: VERTEX_MSL}}),
			fragment: device.createShader({stage: Fragment, code: {glsl: FRAGMENT, msl: FRAGMENT_MSL}}),
			layout: [
				{
					stride: 20,
					attributes: [{location: 0, format: Float2, offset: 0}, {location: 1, format: Float3, offset: 8}]
				}
			]
		});
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
