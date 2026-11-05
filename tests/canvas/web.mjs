// The canvas-web lane: render-web.ts's wasm32 build run in headless
// Chromium (src/helder/os/browser.mjs, src/helder/canvas/imports.mjs: the
// browser's own canvas), each scene's pixels written to bin/canvas/web and
// compared with the CPU back end's (compare.mjs)
//
//   node tests/canvas/web.mjs <module.wasm>
import { createRequire } from "node:module";
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import path from "node:path";

const require = createRequire(import.meta.url);
let pw;
try { pw = require("playwright"); } catch { try { pw = require("/opt/node-tools/node_modules/playwright"); } catch { pw = require(path.join(process.execPath, "../../lib/node_modules/playwright")); } }
const wasm = process.argv[2];
mkdirSync("bin/canvas/web", { recursive: true });
const served = { "/index.html": ["text/html", "<!doctype html><meta charset=utf-8><body></body>"], "/module.wasm": ["application/wasm", readFileSync(wasm)] };
for (const f of ["src/helder/os/browser.mjs", "src/helder/canvas/imports.mjs", "src/helder/text/imports.mjs"]) served["/" + f] = ["text/javascript", readFileSync(f)];
const files = {};
for (const d of ["tests/canvas/fonts", "tests/canvas/images"])
	for (const f of readdirSync(d)) {
		served["/" + d + "/" + f] = ["application/octet-stream", readFileSync(`${d}/${f}`)];
		files[`${d}/${f}`] = "/" + d + "/" + f;
	}
const browser = await pw.chromium.launch({ args: ["--font-render-hinting=none", "--disable-lcd-text", "--force-color-profile=srgb"] });
const page = await browser.newPage();
await page.route("http://canvas.test/**", route => {
	const f = served[new URL(route.request().url()).pathname];
	if (!f) return route.fulfill({ status: 404 });
	route.fulfill({ status: 200, contentType: f[0], body: Buffer.from(f[1]) });
});
await page.goto("http://canvas.test/index.html");
const lines = await page.evaluate(async files => {
	const { run } = await import("/src/helder/os/browser.mjs");
	const out = [];
	const r = await run("/module.wasm", { imports: ["/src/helder/canvas/imports.mjs", "/src/helder/text/imports.mjs"], files, stdout: l => out.push(l), stderr: l => out.push("stderr: " + l) });
	return out;
}, files);
let n = 0;
for (const l of lines) {
	const m = l.match(/^scene (\S+) data:image\/png;base64,(.*)$/);
	if (m) { writeFileSync(`bin/canvas/web/${m[1]}.png`, Buffer.from(m[2], "base64")); n++; }
	else console.log(l);
}
console.log(`web.mjs: ${n} scenes drawn by the browser's canvas (chromium ${browser.version()})`);
await browser.close();
if (n === 0) process.exit(1);
