// The canvas lane's scenes as vectors (the DOM facade's recording): every
// scene a page of bin/canvas/doc/scenes.pdf, each one an SVG of its own
// (bin/canvas/doc/<scene>.svg); doc.mjs draws them with poppler and
// Chromium and compares them with the CPU back end's pixels
import { Canvas } from "helder/canvas";
import { scenes, fonts, images } from "./scenes";

fonts("tests/canvas/fonts");
images("tests/canvas/images");
const book = new Canvas(scenes[0].width, scenes[0].height);
for (let i = 0; i < scenes.length; i++) {
	const s = scenes[i];
	const ctx = i === 0 ? book.getContext("2d")! : book.newPage(s.width, s.height);
	s.draw(ctx);
	const one = new Canvas(s.width, s.height);
	s.draw(one.getContext("2d")!);
	one.saveAs("bin/canvas/doc/" + s.name + ".svg");
	console.log("page " + (i + 1) + " " + s.name);
}
book.saveAs("bin/canvas/doc/scenes.pdf");
console.log("render-doc: " + book.pageCount + " pages");
