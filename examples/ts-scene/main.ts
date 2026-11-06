// title: TypeScript scene
// summary: helder.scene from TypeScript: a glTF model lit by the sun and a point light, glowing orbs of a material that replaces pbr's emissive slot, input actions turning the camera
// tags: 3d, typescript, shaders, pbr
//
// helder/scene in TypeScript: examples/gltf-viewer's sample model (a glTF
// file, loaded as helder/asset's model), a warm point light, three orbs of
// a material of their own (scene.ts: material(pbr.with({...})), compiled
// with the program), the camera turned round the model by the arrow keys
// (an InputMap's axis), Escape to close.
//
//   bun run helder run examples/ts-scene
import { Window, Device, App, InputMap, Bindings, EventKind } from "helder/scene";
import { loaded, model } from "helder/asset";
import { vec3 } from "helder/gfx";
import { Showcase } from "./scene";

async function main() {
	const sample = await loaded(model("examples/gltf-viewer/sample.glb"));
	const window = new Window("TypeScript scene", 640, 480);
	const device = Device.create(window.surface);
	const scene = new Showcase(device, sample);
	const actions = new InputMap();
	actions.bind("turn", Bindings.keyAxis(0xFF51, 0xFF53)).bind("quit", Bindings.key(0xFF1B));
	const eye = scene.camera.node;
	// (round the model, where its file's camera stands)
	const start = eye.position;
	const radius = Math.hypot(start.x, start.z);
	let angle = Math.atan2(start.x, start.z), t = 0;
	App.run(() => {
		actions.step();
		if (actions.pressed("quit")) window.close();
		const turn = actions.axis("turn");
		if (turn !== 0) {
			angle += turn * 0.03;
			eye.position = vec3(Math.sin(angle) * radius, start.y, Math.cos(angle) * radius);
			eye.lookAt(vec3(0, 0.8, 0));
		}
		t += 1 / 60;
		scene.at(t);
		const enc = device.beginFrame();
		if (enc === null) return;
		scene.draw(enc);
		device.endFrame();
	}, e => {
		actions.event(e);
		if (e.kind === EventKind.Close) window.close();
	});
}
main();
