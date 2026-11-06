// The canvas-web lane's browser decoding check: WebDecode.hx's wasm32
// build in headless Chromium; its lines printed, failing unless it ends
// with "webdecode: done, 0 failed" (it goes on after main returns, in the
// decodes' callbacks)
//
//   node tests/canvas/webdecode.mjs <module.wasm>
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import path from "node:path";
const require = createRequire(import.meta.url);
let pw;
try { pw = require("playwright"); } catch { try { pw = require("/opt/node-tools/node_modules/playwright"); } catch { pw = require(path.join(process.execPath, "../../lib/node_modules/playwright")); } }
const served = { "/index.html": ["text/html", "<!doctype html><meta charset=utf-8><body></body>"], "/module.wasm": ["application/wasm", readFileSync(process.argv[2])],
	"/tests/canvas/images/sample.png": ["image/png", readFileSync("tests/canvas/images/sample.png")] };
for (const f of ["src/helder/os/browser.mjs", "src/helder/canvas/imports.mjs"]) served["/" + f] = ["text/javascript", readFileSync(f)];
const browser = await pw.chromium.launch();
const page = await browser.newPage();
await page.route("http://canvas.test/**", route => {
	const f = served[new URL(route.request().url()).pathname];
	route.fulfill(f ? { status: 200, contentType: f[0], body: Buffer.from(f[1]) } : { status: 404 });
});
await page.goto("http://canvas.test/index.html");
const lines = await page.evaluate(async () => {
	const { run } = await import("/src/helder/os/browser.mjs");
	const out = [];
	let end;
	const over = new Promise(r => end = r);
	await run("/module.wasm", { imports: ["/src/helder/canvas/imports.mjs"], files: { "tests/canvas/images/sample.png": "/tests/canvas/images/sample.png" },
		stdout: l => { out.push(l); if (l.startsWith("webdecode: done")) end(); }, stderr: l => out.push("stderr: " + l) });
	await Promise.race([over, new Promise(r => setTimeout(r, 30000))]);
	return out;
}, null);
for (const l of lines) console.log(l);
await browser.close();
if (!lines.includes("webdecode: done, 0 failed")) process.exit(1);
