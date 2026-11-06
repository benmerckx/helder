// title: glTF scene
// summary: A glTF 2.0 scene (a .glb referenced with Model.of, typed from the file) drawn by helder.scene's renderer: metallic-roughness materials, a sun with a shadow map under a sky, a keyframe animation from the file; drag or use the arrows to turn around it
// tags: 3d, gltf, pbr, input
// demo: canvas 512x384
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.os.*;
import helder.scene.*;
import helder.scene.anim.*;
import helder.scene.gltf.*;
import helder.scene.input.*;
import helder.scene.math.*;
import helder.scene.render.*;

// The sample scene (sample.glb, made by tests/3d/SampleModel.hx)
// in a window: referenced with Model.of (checked and typed when compiling,
// built into the program), instantiated into a World, drawn by Renderer. The camera circles the scene on a node of
// its own (drag sideways with the mouse, a finger or a pen, a finger's
// flick gliding on, scroll sideways, or hold the arrows, to turn it: the
// arrows are an input action, InputMap; Escape closes); the simulation (the
// moon's orbit, the turn) runs at a fixed 60 steps a second (FixedStep).
//
//   haxe -cp src -cp examples
//     -main GltfViewer --custom-target hxmc=viewer -D hxmc.libc=glibc
class GltfViewer {
	static function main() {
		var window = new Window("glTF scene", 640, 480);
		var device = Device.create(window.surface, {antialias: true});
		var renderer = new Renderer(device).use(new Shadows(device)).use(new Sky(device));
		var world = new World();
		// (sample.glb read when compiling: its nodes are typed fields, model.nodes.camera)
		var model = Model.of("sample.glb");
		var made = [];
		var root = model.instantiate(world, device, null, made);
		// (the file's animation of the pedestal, typed: model.animations.spin)
		var animator = new Animator(made);
		animator.play(model.clip(model.animations.spin));
		// (the file's camera gives the distance and height; a rig node turns it)
		var fileCamera = root.find(model.nodes.camera);
		var rig = world.node("rig");
		var eye = world.node("eye", rig);
		eye.position = fileCamera.position;
		eye.rotation = fileCamera.rotation;
		var camera = Camera.attach(eye, Camera.perspective(0.7, 0.1, 100));
		// (its components: a closure cannot capture a struct value, Quat, itself)
		var orbit = root.find(model.nodes.orbit), r = orbit.rotation, ox = r.x, oy = r.y, oz = r.z, ow = r.w;
		var clock = new FixedStep(1 / 60);
		// (the arrows, or A and D, turn it too: an action read each step)
		var actions = new InputMap().bind("turn", KeyAxis(0xFF51, 0xFF53)).bind("turn", KeyAxis(0x61, 0x64));
		// (the pointer turning it: the mouse's left button, the first finger or pen; -1: none; a flick's glide)
		var turn = 0.0, speed = 0.25, drag = -1, from = 0.0, last = Sys.time();
		var glide = new Glide();
		window.cursor = Grab;
		window.scrollsAt = (x, y, dx, dy) -> Math.abs(dx) > Math.abs(dy);
		// (under `hxmc dev`: the camera rig's and the scene's transforms carried across a rebuild)
		HotWorld.keep(world, "viewer.world");
		turn = 2 * Math.atan2(rig.rotation.y, rig.rotation.w);
		App.run(() -> {
			var now = Sys.time();
			clock.advance(Math.min(now - last, 0.25), dt -> {
				actions.step();
				animator.update(dt * 0.25);
				var keys = actions.axis("turn");
				if (drag < 0) turn += (keys != 0 ? -1.5 * keys : speed) * dt;
				orbit.rotation = Quat.axisAngle(new Vec3(0, 1, 0), clock.time * 0.8) * new Quat(ox, oy, oz, ow);
			});
			last = now;
			if (glide.step(now * 1000)) turn -= glide.dx / window.width * Math.PI;
			rig.rotation = Quat.axisAngle(new Vec3(0, 1, 0), turn);
			var enc = device.beginFrame();
			if (enc == null) return;
			renderer.draw(enc, world, camera);
			device.endFrame();
		}, e -> {
			actions.event(e);
			switch e.kind {
				case Close: window.close();
				case KeyDown if (e.key == 0xFF1B): window.close();
				case PointerDown if (drag < 0 && (e.pointer.type == Mouse ? e.pointer.buttons & 1 != 0 : e.pointer.primary)):
					drag = e.pointer.id;
					from = e.pointer.x;
					glide.start(e.pointer.time);
					window.cursor = Grabbing;
				case PointerUp | PointerCancel if (e.pointer.id == drag):
					drag = -1;
					// (a finger or a pen let go moving glides on; not the mouse, nor a cancel)
					if (e.kind == PointerUp && e.pointer.type != Mouse) glide.release(e.pointer.time);
					window.cursor = Grab;
				case PointerMove if (e.pointer.id == drag):
					var by = e.pointer.x - from;
					turn -= by / window.width * Math.PI;
					glide.move(by, 0, e.pointer.time);
					from = e.pointer.x;
				case Scroll:
					turn += e.deltaX / window.width * Math.PI;
				case _:
			}
		});
	}
}
