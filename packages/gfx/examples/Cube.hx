import CubeShader;
import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;
import hxmc.os.*;

// A rotating cube in a window, textured, lit and depth-tested, over a
// blended backdrop and a soft shadow (drag to turn it, or scroll sideways:
// a touch drag in a browser, a trackpad's swipe, a sideways wheel; Escape
// closes):
//
//   haxe -cp packages/os/src -cp packages/gfx/src -cp packages/gfx/examples -main Cube
//     --custom-target hxmc=cube -D hxmc.libc=glibc
//
// (as Triangle.hx for macOS, Windows and the browser; an APK for Android:
// --custom-target hxmc=cube.apk -D hxmc.target=android-arm64, then adb
// install -r cube.apk; `--angle a` draws it
// still, turned by a radians plus what a drag turned: the tests' frames).
// It uses what a program needs from hxmc.gfx: an index buffer of each size
// (the cube's UInt16, the backdrop's and the shadow's UInt32), uniform
// blocks written each frame (the camera's matrices:
// CubeShader.writeCubeCamera, Encoder.setUniforms), a texture made here (no
// image decoder) and its sampler, the depth buffer, alpha blending and the
// fragment's position; the shaders are CubeShader.hx.
class Cube {
	static inline var TEXTURE = 64;
	// the ground's height under the cube's centre, the shadow's half size
	static inline var FLOOR = -1.75;
	static inline var SHADOW = 2.4;

	final device:Device;
	final vertices:Buffer;
	final indices:Buffer;
	final quad:Buffer;
	final backdropVertices:Buffer;
	final shadowVertices:Buffer;
	final pipeline:Pipeline;
	final backdropPipeline:Pipeline;
	final shadowPipeline:Pipeline;
	final texture:Texture;
	final sampler:Sampler;
	final pass:PassDesc = {colors: [{load: Clear, clear: new Color(0.1, 0.1, 0.12)}], depth: {load: Clear}};
	// the uniform blocks' bytes, written each frame
	final camera = Bytes.alloc(128);
	final ground = Bytes.alloc(64);
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
		// the backdrop (the whole target) and the shadow (a square on the
		// ground under the cube) share a quad's UInt32 indices
		var qi = Bytes.alloc(6 * 4);
		for (k in 0...6)
			qi.setInt32(4 * k, [0, 1, 2, 0, 2, 3][k]);
		quad = device.createBuffer({size: qi.length, usage: Index, data: qi});
		var corners = [vec2(-1, -1), vec2(1, -1), vec2(1, 1), vec2(-1, 1)];
		bytes = BackdropShader.vertexBytes([for (c in corners) {pos: c}]);
		backdropVertices = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
		bytes = ShadowShader.vertexBytes([for (c in corners) {pos: vec3(c.x * SHADOW, FLOOR, -c.y * SHADOW), at: c}]);
		shadowVertices = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
		pipeline = device.createPipeline(CubeShader.pipeline({cull: Back, depthCompare: Less, depthWrite: true}));
		backdropPipeline = device.createPipeline(BackdropShader.pipeline({blend: Alpha}));
		shadowPipeline = device.createPipeline(ShadowShader.pipeline({blend: Alpha}));
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

	// records the frame's pass, the cube turned by angle radians; the caller ends the frame
	public function draw(enc:Encoder, angle:Float) {
		var w = device.width, h = device.height;
		var model = Mat4.rotationX(0.45) * Mat4.rotationY(angle);
		// (the camera a little back and below the cube's centre, room for its
		// shadow; nothing is sized in pixels: the backdrop follows the target,
		// the shadow the scene, alike on high-density screens)
		var view = Mat4.perspective(Math.PI / 3, w / h, 0.1, 100) * Mat4.translation(0, 0.3, -4.6);
		CubeShader.writeCubeCamera({mvp: view * model, model: model}, camera);
		ShadowShader.writeGround({mvp: view}, ground);
		BackdropShader.writeTarget({size: vec2(w, h)}, target);
		enc.beginPass(pass);
		// (the backdrop and the shadow: no depth test, under the cube)
		enc.setIndexBuffer(quad, UInt32);
		enc.setPipeline(backdropPipeline);
		enc.setUniforms(0, target);
		enc.setVertexBuffer(0, backdropVertices);
		enc.drawIndexed(6);
		enc.setPipeline(shadowPipeline);
		enc.setUniforms(0, ground);
		enc.setVertexBuffer(0, shadowVertices);
		enc.drawIndexed(6);
		enc.setPipeline(pipeline);
		enc.setUniforms(0, camera);
		enc.setTexture(1, texture, sampler);
		enc.setVertexBuffer(0, vertices);
		enc.setIndexBuffer(indices, UInt16);
		enc.drawIndexed(36);
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
		// (turning with time, plus what the mouse dragged and what scrolled
		// sideways: the content follows the finger or the trackpad, a scroll to
		// the right turns it left; not while the mouse drags, the same gesture)
		var start = Sys.time(), drag = 0.0, from = -1;
		App.run(() -> cube.frame((still >= 0 ? Std.parseFloat(args[still + 1]) : Sys.time() - start) + drag), e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case MouseDown if (e.button == 1): from = e.x;
			case MouseUp if (e.button == 1): from = -1;
			case MouseMove if (from >= 0):
				drag += (e.x - from) / window.width * Math.PI;
				from = e.x;
			case Scroll if (from < 0):
				drag -= e.deltaX / window.width * Math.PI;
			case _:
		});
	}
}
