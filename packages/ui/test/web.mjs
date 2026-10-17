// The todo example in a browser (make ui-web-check): WebTodo.wasm in
// headless Chromium on WebGPU, then on WebGL2 (forced), its canvas driven
// by real events (Playwright's mouse and keyboard: clicks, typing, Enter,
// Shift+Left; Control+A, X and V through the page's clipboard), the same
// steps as TodoTest's, then its pixels compared with
// todo.png (TodoTest's frame: our own text rasterizer, so the glyphs are
// the same; the GPUs' edges may differ a little).
//   node packages/ui/test/web.mjs <WebTodo.wasm> [out dir]
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
const FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', BOLD = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf';
const CHROMIUM_ARGS = ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'];
const files = {
	'/todo.wasm': wasm,
	'/os/browser.mjs': path.join(here, '../../os/browser.mjs'),
	'/os/imports.mjs': path.join(here, '../../os/imports.mjs'),
	'/gfx/imports.mjs': path.join(here, '../../gfx/imports.mjs'),
	'/text/imports.mjs': path.join(here, '../../text/imports.mjs'),
	'/compare.mjs': path.join(here, '../../gfx/test/compare.mjs'),
	'/todo.png': path.join(here, 'todo.png'),
	'/DejaVuSans.ttf': FONT,
	'/DejaVuSans-Bold.ttf': BOLD,
};
const types = { '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png', '.ttf': 'font/ttf' };
const page = `<!doctype html><title>Todo</title><body style="margin:0">
<canvas id="c" style="width: 420px; height: 480px; display: block"></canvas>
<script type="module">
import { run } from './os/browser.mjs';
import { decode, compare } from './compare.mjs';
window.log = [];
window.start = async (gfx) => {
	window.r = run('todo.wasm', { imports: ['os/imports.mjs', 'gfx/imports.mjs', 'text/imports.mjs'], canvas: 'c', gfx,
		fonts: ['DejaVuSans.ttf', 'DejaVuSans-Bold.ttf'], stdout: (s) => window.log.push(s), stderr: (s) => window.log.push('stderr: ' + s) });
	window.result = await window.r;
	return window.result.host.gfx.backend;
};
window.check = async () => {
	// (the next frame's pixels: the program draws one when asked)
	const pixels = window.result.host.gfx.readPixels();
	window.result.host.os.redraw();
	const px = await pixels;
	window.pixels = Array.from(px.data);
	// (a light scene: the Add button's fill must differ from the corner)
	return compare('todo', px, await decode('todo.png'), [360, 88, 'contrast']);
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
for (const gfx of ['webgpu', 'webgl2']) {
	const p = await browser.newPage({ viewport: { width: 500, height: 600 } });
	await p.context().grantPermissions(['clipboard-read', 'clipboard-write'], { origin: url });
	const errors = [];
	p.on('pageerror', (e) => errors.push(e.message));
	p.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
	await p.goto(url);
	const backend = await p.evaluate((g) => window.start(g), gfx);
	// the latest boxes the program printed
	const boxes = async () => {
		const log = await p.evaluate(() => window.log);
		const line = [...log].reverse().find((l) => l.startsWith('boxes '));
		const m = {};
		for (const part of line.slice(6).split(' | ')[0].split(' ')) {
			const [k, v] = part.split('=');
			const [x, y, w, h] = v.split(',').map(Number);
			m[k] = { x: x + w / 2, y: y + h / 2 };
		}
		return { m, line };
	};
	const settle = () => p.waitForTimeout(150);
	const click = async (tag) => {
		const { m } = await boxes();
		await p.mouse.click(m[tag].x, m[tag].y);
		await settle();
	};
	await p.waitForFunction(() => window.log.some((l) => l.startsWith('boxes ')), null, { timeout: 15000 });
	await click('draft');
	await p.keyboard.type('Buy milk');
	await p.keyboard.press('Enter');
	await settle();
	await p.keyboard.type('Write the renderer');
	await p.keyboard.press('Shift+ArrowLeft');
	await p.keyboard.press('Shift+ArrowLeft');
	await p.keyboard.type('ER');
	await p.keyboard.press('Backspace');
	await p.keyboard.press('Backspace');
	await p.keyboard.type('er');
	await click('add');
	await click('draft');
	await p.keyboard.type('Ship it');
	// cut to the clipboard, then pasted back
	await p.keyboard.press('Control+A');
	await p.keyboard.press('Control+X');
	await settle();
	const cut = await p.evaluate(() => navigator.clipboard.readText());
	await p.keyboard.press('Control+V');
	await settle();
	await click('add');
	await click('checkbox');
	await click('filter-active');
	await click('filter-all');
	// (the pointer stays over the last button clicked, hovered, as in TodoTest)
	await p.waitForTimeout(300);
	const { line } = await boxes();
	const state = line.split(' | ').slice(1).join(' | ');
	const r = await p.evaluate(() => window.check());
	// (over a button: Window.cursor set the canvas's CSS cursor)
	const cursor = await p.evaluate(() => document.querySelector('canvas').style.cursor);
	if (out) {
		// (the pixels read back, as a PNG drawn by the page)
		const png = await p.evaluate(async () => {
			const c = new OffscreenCanvas(420, 480), g = c.getContext('2d');
			g.putImageData(new ImageData(new Uint8ClampedArray(window.pixels), 420, 480), 0, 0);
			return Array.from(new Uint8Array(await (await c.convertToBlob()).arrayBuffer()));
		});
		await writeFile(path.join(out, `todo-${gfx}.png`), Buffer.from(png));
	}
	const ok = r.ok && state === '2 items left | 3' && cursor === 'pointer' && cut === 'Ship it' && errors.length === 0 && backend === gfx;
	if (!ok) failed++;
	console.log(`web.mjs: ${gfx}: ${r.text}; state: ${state}; cursor: ${cursor}; cut: ${cut}${ok ? '' : ' FAILED'}`);
	for (const e of errors) console.log('  error: ' + e);
	if (backend !== gfx) console.log('  on ' + backend);
	await p.close();
}
await browser.close();
server.close();
process.exit(failed ? 1 : 0);
