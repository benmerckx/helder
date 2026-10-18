import hxmc.gfx.*;
import hxmc.gfx.shader.Vec3;
import hxmc.scene.*;
import hxmc.scene.gltf.*;
import hxmc.scene.render.*;

// packages/3d's test scenes (RenderTest natively, SceneWebTest in the
// browser), each a frame against packages/3d/test/<name>.png:
//   gltf   the sample glTF scene (examples/sample.glb) from its camera,
//          lit by the renderer's sun and sky
//   shadows the same with a shadow map (Shadows, 512x512)
//   physics @hxmc/physics' Falling example after STEPS steps
//   instances 169 nodes on two meshes: instanced draws (RenderTest checks
//          their count)
//   skin   the skinned sample (examples/skinned.glb) bent by its animation
//   overlay the sample scene under the debug overlay (FrameStats, Overlay)
//   textured the textured sample (a PNG in the file, decoded by @hxmc/ui)
//   orbits the Orbits example (shapes made in code on a scene graph, a
//          directional Light) at TIME seconds
class Scenes {
	public static final NAMES = ["gltf", "orbits", "shadows", "physics", "instances", "skin", "overlay", "textured"];
	// the last scene's renderer (its statistics: RenderTest)
	public static var renderer:Null<Renderer>;
	public static inline var TIME = 2.0;
	public static inline var STEPS = 150;

	public static function make(name:String, device:Device):Encoder->Void {
		return switch name {
			case "overlay":
				// the sample scene under the debug overlay (@hxmc/ui), its frame times made up
				var under = make("gltf", device);
				var r = renderer;
				var overlay = new hxmc.scene.debug.Overlay(device);
				var stats = new hxmc.scene.debug.FrameStats(100);
				for (k in 0...100)
					stats.add(k % 17 == 0 ? 0.04 : k % 5 == 0 ? 0.025 : 0.008 + (k % 7) * 0.001);
				enc -> {
					under(enc);
					stats.from(r);
					overlay.draw(enc, stats);
				};
			case "gltf" | "shadows":
				var renderer = new Renderer(device);
				Scenes.renderer = renderer;
				if (name == "shadows") renderer.use(new Shadows(device, 512));
				var world = new World();
				var model = Model.of("sample.glb");
				model.instantiate(world, device);
				// (typed from the file when compiling)
				if (world.root.find(model.nodes.camera).isNone) throw "Scenes: no camera node";
				var camera = Camera.first(world);
				enc -> renderer.draw(enc, world, camera);
			case "orbits":
				var orbits = new Orbits(device);
				orbits.at(TIME);
				enc -> orbits.draw(enc);
			case "physics":
				var falling = new Falling(device);
				for (_ in 0...STEPS)
					falling.physics.step(1 / 60);
				enc -> falling.draw(enc);
			case "instances":
				// a field of 13x13 cubes and spheres on two meshes: instanced draws
				var r = new Renderer(device);
				renderer = r;
				var world = new World();
				var cube = Shapes.box(device, new Material("cube", new hxmc.gfx.shader.Vec4(0.9, 0.45, 0.2, 1), 0, 0.45), 0.5, 0.5, 0.5);
				var ball = Shapes.sphere(device, new Material("ball", new hxmc.gfx.shader.Vec4(0.25, 0.5, 0.95, 1), 0, 0.3), 0.3, 16, 8);
				for (x in 0...13)
					for (z in 0...13) {
						var n = world.node();
						n.position = new Vec3((x - 6) * 0.8, 0, (z - 6) * 0.8);
						n.rotation = hxmc.scene.math.Quat.axisAngle(new Vec3(0, 1, 0), (x * 13 + z) * 0.3);
						MeshRenderer.attach(n, (x + z) % 2 == 0 ? cube : ball);
					}
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0, 6, 8);
				eye.lookAt(new Vec3(0, 0, 0));
				enc -> r.draw(enc, world, camera);
			case "skin":
				// the skinned sample bent by its animation at 1 s (the elbow at 1.2 radians)
				var r = new Renderer(device).use(new Skinning(device));
				renderer = r;
				var world = new World();
				var model = Model.of("skinned.glb");
				var made = [];
				model.instantiate(world, device, null, made);
				var animator = new hxmc.scene.anim.Animator(made);
				animator.play(model.clip(model.animations.bend));
				animator.update(1.0);
				var floor = world.node("floor");
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new hxmc.gfx.shader.Vec4(0.5, 0.5, 0.55, 1), 0, 0.9), 6));
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0.4, 1.4, 4.2);
				eye.lookAt(new Vec3(-0.3, 1.1, 0));
				enc -> r.draw(enc, world, camera);
			case "textured":
				// the textured sample, its PNG decoded by @hxmc/ui's decoder, mip-mapped
				GltfScene.decodeImage = (mime, bytes) -> hxmc.ui.PngDecoder.decode(bytes);
				var r = new Renderer(device);
				renderer = r;
				var world = new World();
				var model = Model.of("textured.glb");
				var crate = model.instantiate(world, device).find(model.nodes.crate);
				crate.rotation = hxmc.scene.math.Quat.fromEuler(0.5, 0.7, 0);
				var floor = world.node("floor");
				floor.position = new Vec3(0, -1.1, 0);
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new hxmc.gfx.shader.Vec4(0.45, 0.47, 0.5, 1), 0, 0.9), 8));
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0, 0.8, 3.2);
				eye.lookAt(new Vec3(0, -0.1, 0));
				enc -> r.draw(enc, world, camera);
			case n: throw 'Scenes: no scene $n';
		}
	}
}
