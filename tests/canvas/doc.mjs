// The canvas-doc lane's check: render-doc's PDF drawn by poppler
// (pdftoppm at 288 dpi, averaged down to a point a pixel) and its SVGs by Chromium, each page
// into bin/canvas/pdf/<scene>.png and bin/canvas/svg/<scene>.png, for
// compare.mjs against the CPU back end's pixels (bin/canvas/ours). Without
// pdftoppm the PDF is only checked by Chromium's drawing of the SVGs.
//
//   node tests/canvas/doc.mjs <render-doc's output: its lines>
import { execFileSync, spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { mkdirSync, readFileSync, readdirSync, unlinkSync, writeFileSync } from "node:fs";
import path from "node:path";

const require = createRequire(import.meta.url);
const { decode, encode } = await import("./compare.mjs");
const names = readFileSync(process.argv[2], "utf8").split("\n").filter(l => l.startsWith("page ")).map(l => l.split(" ")[2]);
for (const d of ["bin/canvas/pdf", "bin/canvas/svg"]) mkdirSync(d, { recursive: true });
if (spawnSync("pdftoppm", ["-v"]).status === 0) {
	// (at 4 pixels a point, then each 4x4 averaged: poppler's own antialiasing is coarser than the canvas's)
	execFileSync("pdftoppm", ["-r", "288", "-png", "bin/canvas/doc/scenes.pdf", "bin/canvas/pdf/page"]);
	const pages = readdirSync("bin/canvas/pdf").filter(f => f.startsWith("page-")).sort();
	pages.forEach((f, i) => {
		const big = decode(readFileSync(`bin/canvas/pdf/${f}`)), w = Math.floor(big.w / 4), h = Math.floor(big.h / 4), px = Buffer.alloc(w * h * 4);
		for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) for (let c = 0; c < 4; c++) {
			let s = 0;
			for (let j = 0; j < 4; j++) for (let k = 0; k < 4; k++) s += big.px[((y * 4 + j) * big.w + x * 4 + k) * 4 + c];
			px[(y * w + x) * 4 + c] = Math.round(s / 16);
		}
		writeFileSync(`bin/canvas/pdf/${names[i]}.png`, encode(w, h, px));
		unlinkSync(`bin/canvas/pdf/${f}`);
	});
	console.log(`doc.mjs: ${pages.length} PDF pages drawn by poppler`);
} else console.log("doc.mjs: no pdftoppm, the PDF not drawn");
let pw;
try { pw = require("playwright"); } catch { try { pw = require("/opt/node-tools/node_modules/playwright"); } catch { pw = require(path.join(process.execPath, "../../lib/node_modules/playwright")); } }
const browser = await pw.chromium.launch({ args: ["--force-color-profile=srgb"] });
const page = await browser.newPage();
for (const n of names) {
	const svg = readFileSync(`bin/canvas/doc/${n}.svg`, "utf8");
	const b64 = await page.evaluate(async svg => {
		const img = new Image();
		img.src = "data:image/svg+xml;base64," + btoa(unescape(encodeURIComponent(svg)));
		await img.decode();
		const c = document.createElement("canvas");
		c.width = img.width;
		c.height = img.height;
		c.getContext("2d").drawImage(img, 0, 0);
		return c.toDataURL().split(",")[1];
	}, svg);
	writeFileSync(`bin/canvas/svg/${n}.png`, Buffer.from(b64, "base64"));
}
console.log(`doc.mjs: ${names.length} SVGs drawn by Chromium ${browser.version()}`);
await browser.close();
