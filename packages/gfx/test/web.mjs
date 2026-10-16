// The triangle and the cube on WebGPU, then on WebGL2 (forced: browser.mjs's
// option gfx: 'webgl2'), in headless Chromium (make gfx-web-check), against
// triangle.png and cube.png with GfxTest's rule (compare.mjs): WebTest.wasm (WebTest.hx)
// headless (on WebGL2 also Device.readPixels, whose checksum must be the
// harness's), then in a 256x192 canvas, whose frames come from the
// browser's loop after main returned; then the canvas is resized (a Resize
// event), characters are typed and the wheel turned (Text and Wheel events)
// and Escape closes the window. A page served here loads the module
// with packages/os/browser.mjs and the packages' imports.mjs; Chromium
// renders with WebGPU on SwiftShader and WebGL2 on ANGLE's SwiftShader (no
// GPU needed).
//   node packages/gfx/test/web.mjs <WebTest.wasm> [out dir]
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
	console.error('usage: node web.mjs <WebTest.wasm> [out dir]');
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
	'/cube.png': path.join(here, 'cube.png'),
};
const types = { '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };
const page = `<!doctype html><title>WebTest</title>
<canvas id="c" style="width: 256px; height: 192px; display: block"></canvas>
<script type="module">
import { run } from './os/browser.mjs';
import { decode, compare } from './compare.mjs';
const log = [];
window.log = log;
window.start = async (gfx, mode, scene) => {
	const golden = await decode(scene + '.png');
	const r = await run('test.wasm', { imports: ['os/imports.mjs', 'gfx/imports.mjs'], canvas: 'c', gfx, args: [mode, scene], stdout: (s) => log.push(s), stderr: (s) => log.push('stderr: ' + s) });
	log.push('exit ' + r.exitCode);
	if (r.host.gfx.backend !== gfx) return { ok: false, text: gfx + ' ' + mode + ': on ' + r.host.gfx.backend };
	const px = await r.host.gfx.readPixels();
	window.pixels = Array.from(px.data);
	// (FNV-1a, as WebTest's)
	let h = 0x811c9dc5;
	for (const b of px.data) h = Math.imul(h ^ b, 0x01000193);
	log.push('harness: readPixels: ' + (h >>> 0).toString(16).toUpperCase().padStart(8, '0'));
	return compare(scene + ' ' + gfx + ' ' + mode, px, golden);
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
console.log(`web.mjs: chromium ${browser.version()}`);
let failed = 0;
for (const [scene, gfx, mode] of ['triangle', 'cube'].flatMap((s) => [[s, 'webgpu', 'headless'], [s, 'webgpu', 'window'], [s, 'webgl2', 'headless'], [s, 'webgl2', 'window']])) {
	const p = await browser.newPage({ viewport: { width: 400, height: 300 } });
	const errors = [];
	p.on('pageerror', (e) => errors.push(e.message));
	p.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
	await p.goto(url);
	const r = await p.evaluate(([g, m, s]) => window.start(g, m, s), [gfx, mode, scene]).catch((e) => ({ ok: false, text: e.message.split('\n')[0] }));
	const api = gfx === 'webgpu' ? 'WebGPU' : 'WebGL2';
	const expect = [];
	if (mode === 'window') {
		if (out) await p.locator('#c').screenshot({ path: path.join(out, `${scene}-${gfx}-canvas.png`) });
		// a Resize from the page's layout, then Escape (the canvas has the focus once clicked)
		await p.evaluate(() => { document.getElementById('c').style.width = '128px'; document.getElementById('c').style.height = '96px'; });
		await p.waitForFunction(() => window.log.some((l) => l.startsWith('WebTest: resized')), null, { timeout: 10000 }).catch(() => {});
		await p.click('#c');
		// (characters and a notch of the wheel up)
		await p.keyboard.type('aZ');
		await p.mouse.wheel(0, -100);
		await p.waitForFunction(() => window.log.some((l) => l.startsWith('WebTest: wheel')), null, { timeout: 10000 }).catch(() => {});
		await p.keyboard.press('Escape');
		await p.waitForFunction(() => window.log.some((l) => l.startsWith('WebTest: Escape')), null, { timeout: 10000 }).catch(() => {});
		expect.push(`WebTest: window: 256x192, App.run returned (${api})`, 'WebTest: resized to 128x96 (128x96)', 'WebTest: text 61', 'WebTest: text 5A', 'WebTest: wheel 0 1', 'WebTest: Escape after');
	} else expect.push(`WebTest: headless: 256x192 (${api})`);
	const log = await p.evaluate(() => window.log);
	if (out) {
		// (the pixels read back, as a PNG drawn by the page)
		const png = await p.evaluate(async () => {
			const c = new OffscreenCanvas(256, 192), g = c.getContext('2d');
			g.putImageData(new ImageData(new Uint8ClampedArray(window.pixels ?? new Array(256 * 192 * 4).fill(0)), 256, 192), 0, 0);
			return Array.from(new Uint8Array(await (await c.convertToBlob()).arrayBuffer()));
		});
		await writeFile(path.join(out, `${scene}-${gfx}-${mode}.png`), Buffer.from(png));
	}
	const missing = expect.filter((e) => !log.some((l) => l.startsWith(e)));
	// (WebGL2 headless: Device.readPixels read what the harness read)
	const sum = (who) => log.find((l) => l.startsWith(who + 'readPixels: '))?.split(': ')[1];
	const same = gfx !== 'webgl2' || mode !== 'headless' || (sum('WebTest: ') && sum('WebTest: ') === sum('harness: '));
	if (!same) missing.push('WebTest: readPixels: ' + sum('harness: '));
	const ok = r.ok && missing.length === 0 && errors.length === 0 && log.includes('exit 0');
	if (!ok) failed++;
	console.log(`web.mjs: ${r.text}${ok ? '' : ' FAILED'}`);
	for (const l of log) console.log('  ' + l);
	for (const m of missing) console.log('  missing: ' + m);
	for (const e of errors) console.log('  error: ' + e);
	await p.close();
}
await browser.close();
server.close();
process.exit(failed ? 1 : 0);
