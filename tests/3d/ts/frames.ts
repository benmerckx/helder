// examples/ts-scene's scenes drawn headless from TypeScript (the 3d lane:
// tests/Run.hx's scene), each frame against a golden image by RenderTest's
// rule (FrameCheck):
//   glow     examples/glow's scene in TypeScript: Haxe's frame, glow.png
//   tsscene  the Showcase (the sample model, a point light, glowing
//            orbs): tsscene.png, which Scenes.hx's Haxe twin draws too
//
//   frames <scene> <golden.png> <out.png> [--bless]
import { FrameCheck } from "./frames/frame-check";
import { loaded, model } from "helder/asset";
import { Glow, Showcase } from "../../../examples/ts-scene/scene";

// (Scenes.TIME: the glow's phase)
const TIME = 2.0;

async function main() {
	const name = FrameCheck.args()[0];
	if (name === "glow") {
		FrameCheck.run(device => {
			const glow = new Glow(device);
			glow.at(TIME);
			return enc => glow.draw(enc);
		});
	} else {
		const sample = await loaded(model("examples/gltf-viewer/sample.glb"));
		FrameCheck.run(device => {
			const scene = new Showcase(device, sample);
			scene.at(TIME);
			return enc => scene.draw(enc);
		});
	}
}
main();
