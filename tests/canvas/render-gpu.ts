// The canvas lane's scenes on the GPU back end (helder.canvas.gpu, headless:
// Mesa's llvmpipe on Linux): bin/canvas/gpu/<scene>.png, compared with the
// CPU back end's (render.ts) by the canvas-gpu lane
import { Canvas, useGpu } from "helder/canvas";
import { scenes, fonts, images } from "./scenes";

useGpu();
fonts("tests/canvas/fonts");
images("tests/canvas/images");
for (const s of scenes) {
	const c = new Canvas(s.width, s.height);
	const ctx = c.getContext("2d")!;
	s.draw(ctx);
	c.saveAs("bin/canvas/gpu/" + s.name + ".png");
}
console.log("render-gpu: " + scenes.length + " scenes");
