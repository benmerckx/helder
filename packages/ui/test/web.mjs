// The todo example in a browser (make ui-web-check): WebTodo.wasm in
// headless Chromium on WebGPU, then on WebGL2 (forced), its canvas driven
// by real events (Playwright's mouse and keyboard: clicks, typing, Enter,
// Shift+Left; Control+A, X and V through the page's clipboard), the same
// steps as TodoTest's; its accessibility tree (the ARIA mirror in the
// canvas) checked, a checkbox activated through it as a screen reader
// would; an input method's composition (the DevTools protocol's
// Input.imeSetComposition: drawn in the field, cancelled, then committed
// and added); then its pixels compared with
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
	'/ui/imports.mjs': path.join(here, '../imports.mjs'),
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
	window.r = run('todo.wasm', { imports: ['os/imports.mjs', 'gfx/imports.mjs', 'text/imports.mjs', 'ui/imports.mjs'], canvas: 'c', gfx,
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
// the next frame's pixels, as a hash
window.snap = async () => {
	const pixels = window.result.host.gfx.readPixels();
	window.result.host.os.redraw();
	const d = (await pixels).data;
	let h = 0;
	for (let i = 0; i < d.length; i++) h = (Math.imul(h, 31) + d[i]) | 0;
	return h;
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
	const p = await browser.newPage({ viewport: { width: 500, height: 600 }, hasTouch: true });
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
	const state = line.split(' | ').slice(1, 3).join(' | ');
	const r = await p.evaluate(() => window.check());
	// (over a button: Window.cursor set the canvas's CSS cursor)
	const cursor = await p.evaluate(() => document.querySelector('canvas').style.cursor);
	// the accessibility tree: roles, names, states (Chromium's own, through
	// the DevTools protocol: a canvas's fallback content is in it)
	const cdp = await p.context().newCDPSession(p);
	const ax = (await cdp.send('Accessibility.getFullAXTree')).nodes.filter((n) => !n.ignored);
	const aria = ax.map((n) => {
		const checked = (n.properties ?? []).find((q) => q.name === 'checked');
		return `${n.role?.value} "${n.name?.value ?? ''}"` + (checked && checked.value.value === 'true' ? ' [checked]' : '');
	}).join('\n');
	const want = ['textbox "What needs to be done?"', 'button "Add"', 'checkbox "Buy milk" [checked]', 'checkbox "Write the renderer"', 'button "Remove"', 'button "all"'];
	const missing = want.filter((w) => !aria.includes(w));
	// a screen reader's activation: a click on the mirror's checkbox, then the count
	await p.evaluate(() => [...document.querySelectorAll('#c [role=checkbox]')].find((e) => e.getAttribute('aria-label') === 'Write the renderer').click());
	await settle();
	const activated = (await boxes()).line.split(' | ')[1];
	// an input method: the field takes text (its textarea focused, named as
	// the field); a composition drawn, cancelled (as before), committed
	await click('draft');
	const typing = await p.evaluate(() => document.activeElement.tagName + ' ' + document.activeElement.getAttribute('aria-label'));
	const before = await p.evaluate(() => window.snap());
	await cdp.send('Input.imeSetComposition', { text: 'にほん', selectionStart: 3, selectionEnd: 3 });
	await settle();
	const composed = await p.evaluate(() => window.snap());
	await cdp.send('Input.imeSetComposition', { text: '', selectionStart: 0, selectionEnd: 0 });
	await settle();
	const cancelled = await p.evaluate(() => window.snap());
	await cdp.send('Input.imeSetComposition', { text: 'にほん', selectionStart: 3, selectionEnd: 3 });
	await cdp.send('Input.insertText', { text: '日本' });
	await p.keyboard.press('Enter');
	await settle();
	const ax2 = (await cdp.send('Accessibility.getFullAXTree')).nodes.filter((n) => !n.ignored);
	const committed = ax2.some((n) => n.role?.value === 'checkbox' && n.name?.value === '日本');
	const ime = typing === 'TEXTAREA What needs to be done?' && composed !== before && cancelled === before && committed;
	// the wheel over the list: a notch's pixels and a trackpad's part of one, as the root hears them
	const { m: at } = await boxes();
	await p.mouse.move(at.left.x, at.left.y - 80);
	await p.mouse.wheel(0, 120);
	await settle();
	await p.mouse.wheel(0, 7.5);
	await settle();
	const wheel = (await boxes()).line.split(' | ')[3];
	// touch: a finger dragged up over the list, held, let go (it scrolls the
	// distance, no glide); a tap on the first checkbox (it toggles)
	const touch = (type, points) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: points });
	await touch('touchStart', [{ x: at.left.x, y: at.left.y - 80 }]);
	for (let k = 1; k <= 10; k++) {
		await touch('touchMove', [{ x: at.left.x, y: at.left.y - 80 - 10 * k }]);
		await p.waitForTimeout(16);
	}
	await p.waitForTimeout(200);
	await touch('touchEnd', []);
	await settle();
	const dragged = (await boxes()).line.split(' | ')[3];
	const { m: cb } = await boxes();
	await touch('touchStart', [{ x: cb.checkbox.x, y: cb.checkbox.y }]);
	await touch('touchEnd', []);
	await settle();
	const tapped = (await boxes()).line.split(' | ')[1];
	// a flick: let go moving, it glides on past its 90 pixels
	await touch('touchStart', [{ x: at.left.x, y: at.left.y - 60 }]);
	for (let k = 1; k <= 3; k++) {
		await touch('touchMove', [{ x: at.left.x, y: at.left.y - 60 - 30 * k }]);
		await p.waitForTimeout(16);
	}
	await touch('touchEnd', []);
	await p.waitForTimeout(1500);
	const flicked = Number((await boxes()).line.split(' | ')[3].split(' ')[1]) - 227.5;
	// the system's appearance: the page's colour scheme made dark, the window asks within a second
	const lightBefore = (await boxes()).line.split(' | ')[4];
	await p.emulateMedia({ colorScheme: 'dark' });
	await p.waitForTimeout(1500);
	await p.evaluate(() => window.result.host.os.redraw());
	await settle();
	const darkAfter = (await boxes()).line.split(' | ')[4];
	const appearance = lightBefore === 'dark false' && darkAfter === 'dark true';
	const touched = dragged === 'wheel 227.5' && tapped === '3 items left' && flicked > 150;
	if (out) {
		// (the pixels read back, as a PNG drawn by the page)
		const png = await p.evaluate(async () => {
			const c = new OffscreenCanvas(420, 480), g = c.getContext('2d');
			g.putImageData(new ImageData(new Uint8ClampedArray(window.pixels), 420, 480), 0, 0);
			return Array.from(new Uint8Array(await (await c.convertToBlob()).arrayBuffer()));
		});
		await writeFile(path.join(out, `todo-${gfx}.png`), Buffer.from(png));
	}
	const ok = r.ok && state === '2 items left | 3' && cursor === 'pointer' && cut === 'Ship it' && missing.length === 0 && activated === '1 item left' && ime && wheel === 'wheel 127.5' && touched && appearance && errors.length === 0 && backend === gfx;
	if (!ok) failed++;
	console.log(`web.mjs: ${gfx}: ${r.text}; state: ${state}; cursor: ${cursor}; cut: ${cut}; access: ${missing.length ? 'missing ' + missing.join(', ') : 'ok'}, activated: ${activated}; input method: ${ime ? 'ok' : `${typing}, composed ${composed !== before}, cancelled ${cancelled === before}, committed ${committed}`}; ${wheel}; appearance: ${appearance ? 'ok' : lightBefore + ', then ' + darkAfter}; touch: ${touched ? 'ok' : dragged + ', ' + tapped + ', flicked ' + flicked}${ok ? '' : ' FAILED'}`);
	if (missing.length) console.log(aria);
	for (const e of errors) console.log('  error: ' + e);
	if (backend !== gfx) console.log('  on ' + backend);
	await p.close();
}
await browser.close();
server.close();
process.exit(failed ? 1 : 0);
