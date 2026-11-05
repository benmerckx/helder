// The canvas lane's scenes on the web back end (helder.canvas.web: the
// browser's own Canvas 2D), as wasm32 in Chromium (web.mjs): each scene's
// pixels as a line, "scene <name> <data: URL>", for web.mjs to compare
// with the CPU back end's
import { Canvas, useWeb } from "helder/canvas";
import { scenes, fonts, images } from "./scenes";

useWeb();
fonts("tests/canvas/fonts");
images("tests/canvas/images");
for (const s of scenes) {
	const c = new Canvas(s.width, s.height);
	const ctx = c.getContext("2d")!;
	s.draw(ctx);
	console.log("scene " + s.name + " " + c.toDataURL());
}
console.log("render-web: " + scenes.length + " scenes");
