// title: glTF scene
// summary: A glTF 2.0 scene (a .glb built into the program) drawn by @hxmc/3d's renderer: metallic-roughness materials, a sun and a sky, a scene graph and its camera; drag to turn around it
// tags: 3d, gltf, pbr, input
// demo: canvas 512x384
import hxmc.gfx.*;
import hxmc.gfx.shader.Vec3;
import hxmc.os.*;
import hxmc.scene.*;
import hxmc.scene.gltf.*;
import hxmc.scene.math.*;
import hxmc.scene.render.*;

// The sample scene (sample.glb, made by packages/3d/test/SampleModel.hx)
// in a window: read with Gltf.parse, made into nodes and meshes by
// GltfScene, drawn by Renderer. The camera circles the scene on a node of
// its own (drag sideways to turn it; Escape closes); the simulation (the
// moon's orbit, the turn) runs at a fixed 60 steps a second (FixedStep).
//
//   haxe -cp packages/os/src -cp packages/gfx/src -cp packages/3d/src -cp packages/3d/examples
//     -main GltfViewer --custom-target hxmc=viewer -D hxmc.libc=glibc
class GltfViewer {
	static function main() {
		var window = new Window("glTF scene", 640, 480);
		var device = Device.create(window.surface);
		var renderer = new Renderer(device);
		var scene = new Scene();
		var model = scene.add(GltfScene.build(Gltf.parse(Asset.embed("sample.glb")), device));
		// (the file's camera gives the distance and height; a rig node turns it)
		var fileCamera = model.find("camera");
		var rig = scene.add(new Node("rig"));
		var eye = rig.add(new Node("eye"));
		eye.position = fileCamera.position;
		eye.rotation = fileCamera.rotation;
		eye.camera = Camera.perspective(0.7, 0.1, 100);
		// (its components: a closure cannot capture a struct value, Quat, itself)
		var orbit = model.find("orbit"), r = orbit.rotation, ox = r.x, oy = r.y, oz = r.z, ow = r.w;
		var clock = new FixedStep(1 / 60);
		var turn = 0.0, speed = 0.25, drag = false, from = 0, last = Sys.time();
		window.cursor = Grab;
		window.scrollsAt = (x, y, dx, dy) -> Math.abs(dx) > Math.abs(dy);
		App.run(() -> {
			var now = Sys.time();
			clock.advance(Math.min(now - last, 0.25), dt -> {
				if (!drag) turn += speed * dt;
				orbit.rotation = Quat.axisAngle(new Vec3(0, 1, 0), clock.time * 0.8) * new Quat(ox, oy, oz, ow);
			});
			last = now;
			rig.rotation = Quat.axisAngle(new Vec3(0, 1, 0), turn);
			var enc = device.beginFrame();
			if (enc == null) return;
			renderer.draw(enc, scene, eye.camera);
			device.endFrame();
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case MouseDown if (e.button == 1):
				drag = true;
				from = e.x;
				window.cursor = Grabbing;
			case MouseUp if (e.button == 1):
				drag = false;
				window.cursor = Grab;
			case MouseMove if (drag):
				turn -= (e.x - from) / window.width * Math.PI;
				from = e.x;
			case Scroll:
				turn += e.deltaX / window.width * Math.PI;
			case _:
		});
	}
}
