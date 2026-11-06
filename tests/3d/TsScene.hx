import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.*;
import helder.scene.*;
import helder.scene.render.*;
import Glow;

// examples/ts-scene's Showcase (examples/ts-scene/scene.ts) in Haxe, node
// for node: examples/gltf-viewer's sample model lit by the sun and a warm
// point light, three orbs of examples/glow's material round it. Its frame
// (Scenes' tsscene) is tsscene.png, the TypeScript one's
// (tests/3d/ts/frames.ts): the two languages draw the same.
class TsScene {
	final world = new World("showcase");
	final bytes = Bytes.alloc(32);

	public final camera:Camera;
	public final renderer:Renderer;

	public function new(device:Device) {
		renderer = new Renderer(device);
		Model.of("sample.glb").instantiate(world, device);
		camera = Camera.first(world);
		var lamp = world.node("lamp");
		lamp.position = new Vec3(0.6, 1.6, 1.8);
		Light.attach(lamp, Light.pointLight(new Vec3(1, 0.6, 0.3), 5, 5));
		var orb = new Material("orb", new Vec4(0.35, 0.3, 0.5, 1), 0, 0.4);
		orb.shader = GlowShader;
		orb.uniforms = ["glow" => bytes];
		var mesh = Shapes.sphere(device, orb, 0.3);
		var at = [new Vec3(1.7, 0.3, 1.4), new Vec3(-0.3, 0.3, 2.3), new Vec3(-2.1, 0.3, -0.6)];
		for (k in 0...at.length) {
			var n = world.node("orb" + k);
			n.position = at[k];
			MeshRenderer.attach(n, mesh);
		}
		this.at(0);
	}

	public function at(t:Float)
		GlowShader.params.glow.write({color: new Vec4(1, 0.55, 0.2, 1), time: new Vec4(t, 0, 0, 0)}, bytes);

	public function draw(enc:Encoder)
		renderer.draw(enc, world, camera);
}
