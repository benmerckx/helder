// The canvas lane's references: scenes.ts drawn by Chromium's canvas
// (headless, through Playwright), each scene's pixels as
// tests/canvas/ref/<scene>.png. The same file helder draws (render.ts),
// its "helder/canvas" the browser's own classes (browser.mjs), its fonts
// and images loaded by the page first. Run again when a scene changes:
//
//   node tests/canvas/chrome.mjs [out dir]     (bun add --no-save playwright; bunx playwright install chromium)
//
// --wpt: the converted WPT tests (wpt/cases.ts) in Chromium instead, a line
// each as wpt.ts prints them (wpt/check.mjs reads both).
import { createRequire, stripTypeScriptTypes } from "node:module";
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import path from "node:path";

const require = createRequire(import.meta.url);
let pw;
try { pw = require("playwright"); } catch { try { pw = require("/opt/node-tools/node_modules/playwright"); } catch { pw = require(path.join(process.execPath, "../../lib/node_modules/playwright")); } }

const dir = "tests/canvas";
const wpt = process.argv.includes("--wpt");
const out = process.argv.slice(2).filter(a => a !== "--wpt")[0] ?? `${dir}/ref`;
if (!wpt) mkdirSync(out, { recursive: true });
const js = f => stripTypeScriptTypes(readFileSync(f, "utf8")).replace(/from\s+"helder\/canvas"/, 'from "/browser.mjs"').replace(/from\s+"\.\/harness"/, 'from "/harness.mjs"');
const scenes = stripTypeScriptTypes(readFileSync(`${dir}/scenes.ts`, "utf8")).replace(/from\s+"helder\/canvas"/, 'from "./browser.mjs"');
const files = {
	"/scenes.mjs": ["text/javascript", scenes],
	"/browser.mjs": ["text/javascript", readFileSync(`${dir}/browser.mjs`)],
	"/cases.mjs": ["text/javascript", wpt ? js(`${dir}/wpt/cases.ts`) : ""],
	"/harness.mjs": ["text/javascript", wpt ? js(`${dir}/wpt/harness.ts`) : ""],
	"/index.html": ["text/html", "<!doctype html><meta charset=utf-8><body></body>"],
};
for (const f of readdirSync(`${dir}/fonts`)) files["/fonts/" + f] = ["font/ttf", readFileSync(`${dir}/fonts/${f}`)];
for (const f of readdirSync(`${dir}/images`)) files["/images/" + f] = ["image/png", readFileSync(`${dir}/images/${f}`)];
const fonts = { "DejaVu Sans": "DejaVuSans-canvas.ttf", "DejaVu Sans Bold": "DejaVuSans-Bold-canvas.ttf", "IPAGothic": "IPAGothic-canvas.ttf" };

const browser = await pw.chromium.launch({ args: ["--font-render-hinting=none", "--disable-lcd-text", "--force-color-profile=srgb", "--disable-gpu"] });
const page = await browser.newPage();
await page.route("http://canvas.test/**", route => {
	const f = files[new URL(route.request().url()).pathname];
	if (!f) return route.fulfill({ status: 404 });
	route.fulfill({ status: 200, contentType: f[0], body: Buffer.from(f[1]) });
});
await page.goto("http://canvas.test/index.html");
if (wpt) {
	const lines = await page.evaluate(async () => {
		const { cases } = await import("/cases.mjs");
		const out = [];
		let passed = 0;
		for (const c of cases) {
			const canvas = document.createElement("canvas");
			canvas.width = c.width;
			canvas.height = c.height;
			try {
				c.run(canvas, canvas.getContext("2d"));
				passed++;
				out.push("PASS " + c.name);
			} catch (e) {
				out.push("FAIL " + c.name + ": " + String(e?.message ?? e));
			}
		}
		out.push("wpt: " + passed + " of " + cases.length + " passed");
		return out;
	});
	console.log(lines.join("\n"));
	await browser.close();
	process.exit(0);
}
const shots = await page.evaluate(async ({ fonts, images }) => {
	for (const [family, file] of Object.entries(fonts)) {
		const face = new FontFace(family, await (await fetch("/fonts/" + file)).arrayBuffer());
		await face.load();
		document.fonts.add(face);
	}
	globalThis.__canvasImages = {};
	for (const name of images) {
		const img = new Image();
		img.src = "/images/" + name;
		await img.decode();
		globalThis.__canvasImages[name] = img;
	}
	const m = await import("/scenes.mjs");
	const shots = {};
	for (const s of m.scenes) {
		const c = document.createElement("canvas");
		c.width = s.width;
		c.height = s.height;
		s.draw(c.getContext("2d"));
		shots[s.name] = c.toDataURL("image/png").split(",")[1];
	}
	return shots;
}, { fonts, images: readdirSync(`${dir}/images`) });
for (const [name, b64] of Object.entries(shots)) writeFileSync(`${out}/${name}.png`, Buffer.from(b64, "base64"));
console.log(`chrome.mjs: ${Object.keys(shots).length} scenes in ${out} (chromium ${browser.version()})`);
await browser.close();
