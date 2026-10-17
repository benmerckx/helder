import CubeShader;
import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;
import hxmc.os.*;

// A rotating cube in a window, textured, lit and depth-tested, with a
// translucent panel blended over it (drag to turn it, Escape closes):
//
//   haxe -cp packages/os/src -cp packages/gfx/src -cp packages/gfx/examples -main Cube
//     --custom-target hxmc=cube -D hxmc.libc=glibc
//
// (as Triangle.hx for macOS, Windows and the browser; `--angle a` draws it
// still, turned by a radians: the tests' frames). It uses what a program
// needs from hxmc.gfx: an index buffer of each size (the cube's UInt16,
// the panel's UInt32), a uniform block written each frame (the camera's
// matrices: CubeShader.writeCamera, Encoder.setUniforms), a texture made
// here (no image decoder) and its sampler, the depth buffer, and alpha
// blending; the shaders are CubeShader.hx.
class Cube {
	static inline var TEXTURE = 64;

	final device:Device;
	final vertices:Buffer;
	final indices:Buffer;
	final panelVertices:Buffer;
	final panelIndices:Buffer;
	final pipeline:Pipeline;
	final panelPipeline:Pipeline;
	final texture:Texture;
	final sampler:Sampler;
	final pass:PassDesc = {colors: [{load: Clear, clear: new Color(0.1, 0.1, 0.12)}], depth: {load: Clear}};
	// the uniform blocks' bytes, written each frame
	final camera = Bytes.alloc(128);
	final target = Bytes.alloc(16);

	public function new(device:Device) {
		this.device = device;
		// the six faces: a normal, then the directions right and up seen from
		// outside (counter-clockwise front faces), the texture upright
		var faces = [
			[vec3(0, 0, 1), vec3(1, 0, 0), vec3(0, 1, 0)], [vec3(0, 0, -1), vec3(-1, 0, 0), vec3(0, 1, 0)],
			[vec3(1, 0, 0), vec3(0, 0, -1), vec3(0, 1, 0)], [vec3(-1, 0, 0), vec3(0, 0, 1), vec3(0, 1, 0)],
			[vec3(0, 1, 0), vec3(1, 0, 0), vec3(0, 0, -1)], [vec3(0, -1, 0), vec3(1, 0, 0), vec3(0, 0, 1)]
		];
		var vs:Array<CubeVertex> = [];
		var is = Bytes.alloc(36 * 2);
		for (f in 0...6) {
			var n = faces[f][0], r = faces[f][1], u = faces[f][2];
			for (c in [[-1, -1], [1, -1], [1, 1], [-1, 1]])
				vs.push({pos: n + r * c[0] + u * c[1], normal: n, uv: vec2((c[0] + 1) / 2, (1 - c[1]) / 2)});
			for (k in 0...6)
				is.setUInt16(2 * (6 * f + k), 4 * f + [0, 1, 2, 0, 2, 3][k]);
		}
		var bytes = CubeShader.vertexBytes(vs);
		vertices = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
		indices = device.createBuffer({size: is.length, usage: Index, data: is});
		// the panel: a light translucent rectangle and an orange bar at its foot, in pixels
		var c = vec4(0.85, 0.9, 1, 0.3), o = vec4(1, 0.55, 0.1, 0.9);
		var pv:Array<PanelVertex> = [];
		function rect(x0:Float, y0:Float, x1:Float, y1:Float, color:Vec4)
			for (p in [vec2(x0, y1), vec2(x1, y1), vec2(x1, y0), vec2(x0, y0)])
				pv.push({pos: p, color: color});
		rect(8, 8, 104, 44, c);
		rect(8, 40, 104, 44, o);
		bytes = PanelShader.vertexBytes(pv);
		panelVertices = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
		var pi = Bytes.alloc(12 * 4);
		for (k in 0...12)
			pi.setInt32(4 * k, 4 * Std.int(k / 6) + [0, 1, 2, 0, 2, 3][k % 6]);
		panelIndices = device.createBuffer({size: pi.length, usage: Index, data: pi});
		pipeline = device.createPipeline(CubeShader.pipeline({cull: Back, depthCompare: Less, depthWrite: true}));
		panelPipeline = device.createPipeline(PanelShader.pipeline({blend: Alpha}));
		texture = device.createTexture({width: TEXTURE, height: TEXTURE, data: texels()});
		sampler = device.createSampler({filter: Linear, wrap: Clamp});
	}

	// the texture: smooth colours, a light disc towards the top left and a
	// darker border (smooth, so that GPUs filter it alike)
	static function texels():Bytes {
		var b = Bytes.alloc(TEXTURE * TEXTURE * 4);
		for (y in 0...TEXTURE)
			for (x in 0...TEXTURE) {
				var u = (x + 0.5) / TEXTURE, v = (y + 0.5) / TEXTURE;
				var color = vec3(0.25 + 0.6 * u, 0.3 + 0.4 * v, 0.85 - 0.5 * u);
				var disc = 1 - smoothstep(0.12, 0.3, distance(vec2(u, v), vec2(0.32, 0.3)));
				color = mix(color, vec3(1, 0.95, 0.8), disc * 0.8);
				color = color * (0.45 + 0.55 * smoothstep(0, 0.12, Math.min(Math.min(u, 1 - u), Math.min(v, 1 - v))));
				var p = 4 * (y * TEXTURE + x);
				b.set(p, Math.round(color.x * 255));
				b.set(p + 1, Math.round(color.y * 255));
				b.set(p + 2, Math.round(color.z * 255));
				b.set(p + 3, 255);
			}
		return b;
	}

	// pixels per point (Window.scale), for the panel
	public var scale = 1.0;

	// records the frame's pass, the cube turned by angle radians; the caller ends the frame
	public function draw(enc:Encoder, angle:Float) {
		var w = device.width, h = device.height;
		var model = Mat4.rotationX(0.45) * Mat4.rotationY(angle);
		var mvp = Mat4.perspective(Math.PI / 3, w / h, 0.1, 100) * Mat4.translation(0, 0, -4) * model;
		CubeShader.writeCubeCamera({mvp: mvp, model: model}, camera);
		// (the panel is laid out in points: scale pixels each)
		PanelShader.writeTarget({size: vec2(w / scale, h / scale), top: 8 * scale, height: 36 * scale}, target);
		enc.beginPass(pass);
		enc.setPipeline(pipeline);
		enc.setUniforms(0, camera);
		enc.setTexture(1, texture, sampler);
		enc.setVertexBuffer(0, vertices);
		enc.setIndexBuffer(indices, UInt16);
		enc.drawIndexed(36);
		enc.setPipeline(panelPipeline);
		enc.setUniforms(0, target);
		enc.setVertexBuffer(0, panelVertices);
		enc.setIndexBuffer(panelIndices, UInt32);
		enc.drawIndexed(12);
		enc.endPass();
	}

	public function frame(angle:Float) {
		var enc = device.beginFrame();
		if (enc == null) return;
		draw(enc, angle);
		device.endFrame();
	}

	static function main() {
		var args = Sys.args(), still = args.indexOf("--angle");
		var window = new Window("Cube", 640, 480);
		var cube = new Cube(Device.create(window.surface));
		// (turning with time, plus what the mouse dragged)
		var start = Sys.time(), drag = 0.0, from = -1;
		App.run(() -> {
			cube.scale = window.scale;
			cube.frame(still >= 0 ? Std.parseFloat(args[still + 1]) : Sys.time() - start + drag);
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case MouseDown if (e.button == 1): from = e.x;
			case MouseUp if (e.button == 1): from = -1;
			case MouseMove if (from >= 0):
				drag += (e.x - from) / window.width * Math.PI;
				from = e.x;
			case _:
		});
	}
}
