// title: Render targets
// summary: A scene rendered into a texture with its own depth buffer each frame, then shown on the faces of the cube
// tags: gfx, shaders, 3d, render targets
// demo: canvas 512x384
import TargetsShader;
import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.os.*;

// Render to texture, in a window (Escape closes):
//
//   haxe -cp src -cp examples -main Targets
//     --custom-target hxmc=targets -D hxmc.libc=glibc
//
// (as Triangle.hx for macOS, Windows and the browser; `--time t` draws it
// still, at t seconds: the tests' frames). Each frame has two passes: the
// first into a render target (TextureDesc.renderTarget, ColorTarget.texture)
// with a depth texture of its size (DepthTarget.texture), drawing a backdrop
// and two overlapping panels, depth-tested and their back faces culled, with
// pipelines made for those formats (PipelineDesc.colorFormat,
// depthFormat); the second into the frame, the cube example (Cube.hx)
// showing the target on its faces.
class Targets {
	public static inline var SIZE = 128;

	final device:Device;
	final cube:Cube;
	final panels:Buffer;
	final indices:Buffer;
	final fill:Buffer;
	final panelPipeline:Pipeline;
	final fillPipeline:Pipeline;
	final pass:PassDesc;
	final camera = Bytes.alloc(64);

	// (samples 4: the target multisampled, TextureDesc.samples, resolved into
	// the texture the cube shows at the pass's end, ColorTarget.resolve)
	public function new(device:Device, samples = 1) {
		this.device = device;
		var color = device.createTexture({width: SIZE, height: SIZE, renderTarget: true, samples: samples});
		var depth = device.createTexture({width: SIZE, height: SIZE, format: Depth32F, samples: samples});
		var shown = samples > 1 ? device.createTexture({width: SIZE, height: SIZE, renderTarget: true}) : color;
		pass = {colors: [{load: Clear, texture: color, resolve: samples > 1 ? shown : null}], depth: {load: Clear, texture: depth}};
		cube = new Cube(device);
		cube.texture = shown;
		// two parallel panels, one behind the other and overlapping (drawn
		// front first: the depth test hides the other's part), each a front
		// face and a darker back face (counter-clockwise seen from their side)
		var vs:Array<PanelVertex> = [];
		var is = Bytes.alloc(24 * 2);
		for (p in 0...2) {
			var at = p == 0 ? vec3(-0.32, 0.22, 0.3) : vec3(0.32, -0.22, -0.3);
			var tint = p == 0 ? vec3(0.95, 0.35, 0.25) : vec3(0.25, 0.45, 0.95);
			for (side in 0...2) {
				var shade = side == 0 ? 1.0 : 0.45, first = vs.length;
				for (k in [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
					var x = (side == 0 ? k[0] : -k[0]) * 0.55, y = k[1] * 0.55;
					vs.push({pos: at + vec3(x, y, 0), color: tint * shade * (0.75 + 0.25 * k[1])});
				}
				for (i in 0...6)
					is.setUInt16(2 * ((first >> 2) * 6 + i), first + [0, 1, 2, 0, 2, 3][i]);
			}
		}
		var bytes = PanelShader.vertexBytes(vs);
		panels = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
		indices = device.createBuffer({size: is.length, usage: Index, data: is});
		bytes = FillShader.vertexBytes([for (c in [vec2(-1, -1), vec2(3, -1), vec2(-1, 3)]) {pos: c}]);
		fill = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
		var d = PanelShader.pipeline({cull: Back, depthCompare: Less, depthWrite: true});
		d.colorFormat = RGBA8;
		d.depthFormat = Depth32F;
		d.samples = samples;
		panelPipeline = device.createPipeline(d);
		d = FillShader.pipeline();
		d.colorFormat = RGBA8;
		d.depthFormat = Depth32F;
		d.samples = samples;
		fillPipeline = device.createPipeline(d);
	}

	// records the frame's passes at time t; the caller ends the frame
	public function draw(enc:Encoder, t:Float) {
		var view = Mat4.perspective(Math.PI / 3, 1, 0.1, 10) * Mat4.translation(0, 0, -2.2);
		PanelShader.writePanelCamera({mvp: view * Mat4.rotationX(0.3) * Mat4.rotationY(t * 0.9)}, camera);
		enc.beginPass(pass);
		enc.setPipeline(fillPipeline);
		enc.setVertexBuffer(0, fill);
		enc.draw(3);
		enc.setPipeline(panelPipeline);
		enc.setUniforms(0, camera);
		enc.setVertexBuffer(0, panels);
		enc.setIndexBuffer(indices, UInt16);
		enc.drawIndexed(24);
		enc.endPass();
		cube.draw(enc, 0.6 + t * 0.3);
	}

	public function frame(t:Float) {
		var enc = device.beginFrame();
		if (enc == null) return;
		draw(enc, t);
		device.endFrame();
	}

	static function main() {
		var args = Sys.args(), still = args.indexOf("--time");
		var window = new Window("Render targets", 640, 480);
		var targets = new Targets(Device.create(window.surface));
		var start = Sys.time();
		App.run(() -> targets.frame(still >= 0 ? Std.parseFloat(args[still + 1]) : Sys.time() - start), e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case _:
		});
	}
}
