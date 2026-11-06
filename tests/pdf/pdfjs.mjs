// The pdf lane's references: page 1 of each corpus PDF rendered by pdf.js
// (pdfjs-dist, in headless Chromium through Playwright) at 1.5 pixels a
// point into tests/pdf/ref/<name>.png, its text (getTextContent) into
// <name>.txt. Run again when the corpus changes:
//
//   PDFJS=<pdfjs-dist's directory> node tests/pdf/pdfjs.mjs   (npm pack pdfjs-dist; bun add --no-save playwright)
import { createRequire } from "node:module";
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import path from "node:path";

const require = createRequire(import.meta.url);
let pw;
try { pw = require("playwright"); } catch { try { pw = require("/opt/node-tools/node_modules/playwright"); } catch { pw = require(path.join(process.execPath, "../../lib/node_modules/playwright")); } }
const dist = process.env.PDFJS ?? "node_modules/pdfjs-dist";
const out = process.argv[2] ?? "tests/pdf/ref", scale = 1.5;
mkdirSync(out, { recursive: true });
const served = {
	"/index.html": ["text/html", "<!doctype html><meta charset=utf-8><body></body>"],
	"/pdf.mjs": ["text/javascript", readFileSync(`${dist}/build/pdf.mjs`)],
	"/pdf.worker.mjs": ["text/javascript", readFileSync(`${dist}/build/pdf.worker.mjs`)],
};
const names = readdirSync("tests/pdf/corpus").filter(f => f.endsWith(".pdf")).sort();
for (const n of names) served["/corpus/" + n] = ["application/pdf", readFileSync(`tests/pdf/corpus/${n}`)];
for (const d of ["standard_fonts", "cmaps", "wasm"]) for (const f of readdirSync(`${dist}/${d}`)) served[`/${d}/${f}`] = [f.endsWith(".wasm") ? "application/wasm" : "application/octet-stream", readFileSync(`${dist}/${d}/${f}`)];
const browser = await pw.chromium.launch();
const page = await browser.newPage();
await page.route("http://pdf.test/**", r => {
	const f = served[new URL(r.request().url()).pathname];
	r.fulfill(f ? { status: 200, contentType: f[0], body: Buffer.from(f[1]) } : { status: 404 });
});
await page.goto("http://pdf.test/index.html");
const shots = await page.evaluate(async ({ names, scale }) => {
	const pdfjs = await import("/pdf.mjs");
	pdfjs.GlobalWorkerOptions.workerSrc = "/pdf.worker.mjs";
	const out = {};
	for (const n of names) {
		const doc = await pdfjs.getDocument({ url: "/corpus/" + n, standardFontDataUrl: "/standard_fonts/", cMapUrl: "/cmaps/", cMapPacked: true, wasmUrl: "/wasm/" }).promise;
		const p = await doc.getPage(1), vp = p.getViewport({ scale });
		const c = document.createElement("canvas");
		c.width = Math.ceil(vp.width);
		c.height = Math.ceil(vp.height);
		// (the annotations' appearances drawn into the canvas, form fields' too: as printed)
		await p.render({ canvasContext: c.getContext("2d"), viewport: vp, background: "white", annotationMode: pdfjs.AnnotationMode.ENABLE }).promise;
		// (its text: the items in order, a newline at each end of line)
		const tc = await p.getTextContent();
		out[n] = [c.toDataURL().split(",")[1], tc.items.map(t => t.str + (t.hasEOL ? "\n" : "")).join("")];
	}
	return out;
}, { names, scale });
for (const [n, [b64, text]] of Object.entries(shots)) {
	writeFileSync(`${out}/${n.replace(/\.pdf$/, "")}.png`, Buffer.from(b64, "base64"));
	writeFileSync(`${out}/${n.replace(/\.pdf$/, "")}.txt`, text);
}
console.log(`pdfjs.mjs: ${names.length} pages by pdf.js in ${out}`);
await browser.close();
