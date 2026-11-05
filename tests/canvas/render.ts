// The canvas lane's scenes drawn by helder.canvas's DOM facade, natively:
// bin/canvas/ours/<scene>.png (compare.mjs compares them with
// tests/canvas/ref's, Chromium's)
import { Canvas } from "helder/canvas";
import { scenes, fonts, images } from "./scenes";

fonts("tests/canvas/fonts");
images("tests/canvas/images");
for (const s of scenes) {
	const c = new Canvas(s.width, s.height);
	const ctx = c.getContext("2d")!;
	s.draw(ctx);
	c.saveAs("bin/canvas/ours/" + s.name + ".png");
}
console.log("render: " + scenes.length + " scenes");
