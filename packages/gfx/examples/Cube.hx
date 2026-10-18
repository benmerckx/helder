// title: Cube
// summary: A textured cube with rounded, lit edges casting a soft shadow, depth-tested, its matrices a uniform block; drag it to turn it
// tags: gfx, shaders, 3d, input
// demo: canvas 512x384
import CubeShader;
import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;
import hxmc.os.*;
import hxmc.os.Event.Mods;

// A rotating cube in a window, textured, lit and depth-tested, over a
// blended backdrop and a soft shadow (drag to turn it, or scroll sideways:
// a touch drag in a browser, a trackpad's swipe, a sideways wheel; it
// stops spinning while held, and carries on at the drag's speed when let
// go; Escape closes):
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
	// what the cube's faces show (Targets.hx: a render target)
	public var texture:Texture;
	final sampler:Sampler;
	final pass:PassDesc = {colors: [{load: Clear, clear: new Color(0.1, 0.1, 0.12)}], depth: {load: Clear}};
	// the uniform blocks' bytes, written each frame
	final camera = Bytes.alloc(128);
	final ground = Bytes.alloc(64);
	final target = Bytes.alloc(16);

	public function new(device:Device) {
		this.device = device;
		// the six faces: a normal, then the directions right and up seen from
		// outside (counter-clockwise front faces), the texture upright (the
		// shading's normals come from the point on the cube: CubeShader)
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
				vs.push({pos: n + r * c[0] + u * c[1], uv: vec2((c[0] + 1) / 2, (1 - c[1]) / 2)});
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

	// the texture: a warm gradient (the site's orange, lighter towards the
	// top left, deeper towards the bottom right) under a soft glow at the
	// top left (smooth, so that GPUs filter it alike)
	static function texels():Bytes {
		var b = Bytes.alloc(TEXTURE * TEXTURE * 4);
		for (y in 0...TEXTURE)
			for (x in 0...TEXTURE) {
				var u = (x + 0.5) / TEXTURE, v = (y + 0.5) / TEXTURE;
				var color = mix(vec3(0.99, 0.62, 0.32), vec3(0.78, 0.27, 0.09), u * 0.45 + v * 0.55);
				color = mix(color, vec3(1, 0.76, 0.5), 0.25 * (1 - smoothstep(0, 0.75, distance(vec2(u, v), vec2(0.2, 0.15)))));
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
		// (turning with time, unless held; what the mouse drags and what
		// scrolls sideways turn it too: the content follows the finger or the
		// trackpad, a scroll to the right turns it left; not while the mouse
		// drags, the same gesture. A browser's touch drag comes as scrolls,
		// Mods.TOUCH while the finger is down)
		var spin = new Spin(still >= 0 ? 0 : Spin.SPEED), angle = still >= 0 ? Std.parseFloat(args[still + 1]) : 0.0;
		var last = Sys.time(), from = 0, dragging = false, touching = false;
		window.cursor = Grab;
		App.run(() -> {
			var now = Sys.time();
			spin.advance(Math.min(now - last, 0.1));
			last = now;
			cube.frame(angle + spin.angle);
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case MouseDown if (e.button == 1):
				from = e.x;
				dragging = true;
				spin.grab();
				window.cursor = Grabbing;
			case MouseUp if (e.button == 1 && dragging):
				dragging = false;
				spin.release(true);
				window.cursor = Grab;
			// (also off the window: a browser's canvas captures the press)
			case MouseMove if (dragging):
				spin.drag((e.x - from) / window.width * Math.PI);
				from = e.x;
			case Scroll if (!dragging):
				var by = -e.deltaX / window.width * Math.PI;
				if ((e.mods & Mods.TOUCH) != 0) {
					if (!touching) spin.grab();
					touching = true;
					spin.drag(by);
				} else {
					// (the finger let go: its glide carries on, as scrolls)
					if (touching) spin.release(false);
					touching = false;
					if (by != 0) spin.nudge(by);
				}
			case _:
		});
	}
}

// The cube's turn (Cube.main): SPEED radians a second of its own, unless
// held (grab, release): then only the drag turns it, at once, and time
// does not; let go, it carries on at the drag's last speed (a flick), or
// from rest, easing back to its own speed in about a second. A scroll's
// nudge turns it and starts it from rest again.
class Spin {
	public static inline var SPEED = 0.6;
	static inline var FLICK = 12.0;

	public var angle = 0.0;
	public var held(default, null) = false;

	final own:Float;
	var speed:Float;
	// while held: the drag's turn since the last advance, its speed
	var dragged = 0.0;
	var dragSpeed = 0.0;

	public function new(own:Float) {
		this.own = own;
		speed = own;
	}

	// dt seconds have passed
	public function advance(dt:Float) {
		if (dt <= 0) return;
		if (held) {
			// (smoothed: a finger resting brings it to 0 in a few frames)
			dragSpeed = 0.6 * (dragged / dt) + 0.4 * dragSpeed;
			dragged = 0;
			return;
		}
		speed += (own - speed) * (1 - Math.exp(-2 * dt));
		angle += speed * dt;
	}

	public function grab() {
		held = true;
		dragged = dragSpeed = 0;
	}

	public function drag(by:Float) {
		angle += by;
		dragged += by;
	}

	// let go: with the drag's speed (flick), or from rest
	public function release(flick:Bool) {
		if (!held) return;
		held = false;
		speed = flick ? Math.max(-FLICK, Math.min(FLICK, dragSpeed)) : 0;
	}

	public function nudge(by:Float) {
		angle += by;
		speed = 0;
	}
}
