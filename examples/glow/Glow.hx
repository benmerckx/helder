// title: Glow
// summary: A material of its own: the standard PBR shader with two of its slots replaced (a pulsing emissive light, a brighter base colour), drawn plain and instanced
// tags: 3d, shaders, pbr
// demo: canvas 512x384
import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.os.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.*;
import helder.scene.render.PbrShader;

// The standard material is a slot object (pbr, helder.scene.render.
// PbrShader): MaterialShader.material compiles it, at build time, with
// some of its slots replaced, into the variants the renderer draws a
// material with. Here the emissive slot is a pulse of a colour of its own
// (a uniform block the material carries: its parameter, glow, joins the
// shader's) and the colour slot lifts the base colour; the rest (lights,
// shadows, the sky's ambient) is pbr's. The orbs are one mesh drawn many
// times (instanced: the same slots in the instanced variant).
//
//   helder build examples/glow/Glow.hx
typedef GlowParams = {
	var color:Vec4; // rgb: the light's colour
	var time:Vec4; // x: seconds
}

final GlowShader = MaterialShader.material(pbr.with({
	emissive: function(s:PbrSurface, p:{glow:GlowParams}):Vec3 return p.glow.color.xyz * (0.6 + 0.4 * sin(p.glow.time.x * 3 + s.world.x)),
	color: function(s:PbrSurface, p:{}):Vec3 return s.baseColor.xyz * 1.4
}));

class Glow {
	final world = new World("glow");
	final bytes = Bytes.alloc(32);
	public final camera:Camera;
	public final renderer:Renderer;

	public function new(device:Device) {
		renderer = new Renderer(device);
		renderer.sky = new Vec3(0.12, 0.14, 0.2);
		renderer.ground = new Vec3(0.04, 0.04, 0.05);
		var floor = world.node("floor");
		floor.position = new Vec3(0, -0.6, 0);
		MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new Vec4(0.4, 0.42, 0.45, 1), 0, 0.85), 8));
		var orb = new Material("orb", new Vec4(0.35, 0.3, 0.5, 1), 0, 0.4);
		orb.shader = GlowShader;
		orb.uniforms = ["glow" => bytes];
		var mesh = Shapes.sphere(device, orb, 0.35);
		for (k in 0...5) {
			var n = world.node("orb" + k);
			n.position = new Vec3((k - 2) * 0.85, -0.25, 0);
			MeshRenderer.attach(n, mesh);
		}
		var eye = world.node("eye");
		camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
		eye.position = new Vec3(0, 1.1, 3.6);
		eye.lookAt(new Vec3(0, -0.3, 0));
		at(0);
	}

	// the glow at time t (seconds): its block (GlowShader's writer)
	public function at(t:Float)
		GlowShader.params.glow.write({color: new Vec4(1, 0.55, 0.2, 1), time: new Vec4(t, 0, 0, 0)}, bytes);

	public function draw(enc:Encoder)
		renderer.draw(enc, world, camera);

	static function main() {
		var window = new Window("Glow", 640, 480);
		var device = Device.create(window.surface);
		var glow = new Glow(device);
		// (the frames' clock: the display's, or a headless run's virtual one, so `helder run --headless --snap` shows the glow at a time)
		var start = -1.0;
		App.run(() -> {
			if (start < 0) start = App.frame.time;
			glow.at(App.frame.time - start);
			var enc = device.beginFrame();
			if (enc == null) return;
			glow.draw(enc);
			device.endFrame();
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case _:
		});
	}
}
