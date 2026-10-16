// The triangle on WebGPU in headless Chromium (make gfx-web-check), against
// triangle.png with GfxTest's rule (compare.mjs): WebTest.wasm (WebTest.hx)
// headless, then in a 256x192 canvas, whose frames come from the browser's
// loop after main returned; then the canvas is resized (a Resize event) and
// Escape closes the window. A page served here loads the module with
// packages/os/browser.mjs and the packages' imports.mjs; Chromium renders
// with WebGPU on SwiftShader (no GPU needed).
//   node packages/gfx/test/webgpu.mjs <WebTest.wasm> [out dir]
// (Playwright from npm, with Chromium: npx playwright install chromium)
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const [wasm, out] = process.argv.slice(2);
if (!wasm) {
	console.error('usage: node webgpu.mjs <WebTest.wasm> [out dir]');
	process.exit(2);
}
// Chromium's WebGPU without a GPU: SwiftShader's Vulkan (with
// --use-webgpu-adapter=swiftshader instead, buffers no longer map once a
// canvas is configured)
const CHROMIUM_ARGS = ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'];

const files = {
	'/test.wasm': wasm,
	'/os/browser.mjs': path.join(here, '../../os/browser.mjs'),
	'/os/imports.mjs': path.join(here, '../../os/imports.mjs'),
	'/gfx/imports.mjs': path.join(here, '../imports.mjs'),
	'/compare.mjs': path.join(here, 'compare.mjs'),
	'/triangle.png': path.join(here, 'triangle.png'),
};
const types = { '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };
const page = `<!doctype html><title>WebTest</title>
<canvas id="c" style="width: 256px; height: 192px; display: block"></canvas>
<script type="module">
import { run } from './os/browser.mjs';
import { decode, compare } from './compare.mjs';
const log = [];
window.log = log;
window.start = async (mode) => {
	const golden = await decode('triangle.png');
	const r = await run('test.wasm', { imports: ['os/imports.mjs', 'gfx/imports.mjs'], canvas: 'c', args: [mode], stdout: (s) => log.push(s), stderr: (s) => log.push('stderr: ' + s) });
	log.push('exit ' + r.exitCode);
	if (!r.host.gfx.device) return { ok: false, text: 'no WebGPU device' };
	const px = await r.host.gfx.readPixels();
	window.pixels = Array.from(px.data);
	return compare(mode, px, golden);
};
</script>`;
const server = createServer(async (req, res) => {
	const p = new URL(req.url, 'http://x').pathname;
	try {
		const b = p === '/' ? Buffer.from(page) : await readFile(files[p]);
		res.writeHead(200, { 'content-type': p === '/' ? 'text/html' : types[path.extname(p)] });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
}).listen(0);
const url = `http://localhost:${server.address().port}/`;

const browser = await pw.chromium.launch({ args: CHROMIUM_ARGS });
console.log(`webgpu.mjs: chromium ${browser.version()}`);
let failed = 0;
for (const mode of ['headless', 'window']) {
	const p = await browser.newPage({ viewport: { width: 400, height: 300 } });
	const errors = [];
	p.on('pageerror', (e) => errors.push(e.message));
	p.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
	await p.goto(url);
	const r = await p.evaluate((m) => window.start(m), mode).catch((e) => ({ ok: false, text: e.message.split('\n')[0] }));
	const expect = [];
	if (mode === 'window') {
		if (out) await p.locator('#c').screenshot({ path: path.join(out, 'webgpu-canvas.png') });
		// a Resize from the page's layout, then Escape (the canvas has the focus once clicked)
		await p.evaluate(() => { document.getElementById('c').style.width = '128px'; document.getElementById('c').style.height = '96px'; });
		await p.waitForFunction(() => window.log.some((l) => l.startsWith('WebTest: resized')), null, { timeout: 10000 }).catch(() => {});
		await p.click('#c');
		await p.keyboard.press('Escape');
		await p.waitForFunction(() => window.log.some((l) => l.startsWith('WebTest: Escape')), null, { timeout: 10000 }).catch(() => {});
		expect.push('WebTest: window: 256x192, App.run returned', 'WebTest: resized to 128x96 (128x96)', 'WebTest: Escape after');
	} else expect.push('WebTest: headless: 256x192');
	const log = await p.evaluate(() => window.log);
	if (out) {
		// (the pixels read back, as a PNG drawn by the page)
		const png = await p.evaluate(async () => {
			const c = new OffscreenCanvas(256, 192), g = c.getContext('2d');
			g.putImageData(new ImageData(new Uint8ClampedArray(window.pixels ?? new Array(256 * 192 * 4).fill(0)), 256, 192), 0, 0);
			return Array.from(new Uint8Array(await (await c.convertToBlob()).arrayBuffer()));
		});
		await writeFile(path.join(out, `webgpu-${mode}.png`), Buffer.from(png));
	}
	const missing = expect.filter((e) => !log.some((l) => l.startsWith(e)));
	const ok = r.ok && missing.length === 0 && errors.length === 0 && log.includes('exit 0');
	if (!ok) failed++;
	console.log(`webgpu.mjs: ${r.text}${ok ? '' : ' FAILED'}`);
	for (const l of log) console.log('  ' + l);
	for (const m of missing) console.log('  missing: ' + m);
	for (const e of errors) console.log('  error: ' + e);
	await p.close();
}
await browser.close();
server.close();
process.exit(failed ? 1 : 0);
