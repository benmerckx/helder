// helder.os's pointers in headless Chromium (bun run test touch-web):
// PointersWeb.wasm on a 300x200 canvas at a pixel ratio of 2, driven by the
// DevTools protocol's touches (two fingers at once, moved, lifted, one
// cancelled), a pen and the mouse (Input.dispatchMouseEvent's pointerType),
// its lines checked: dense slots (the mouse 0, fingers and pens from 1), the
// first finger primary, buffer pixels, a touch's compatibility click while
// Pointers.emulate is on and none once it is off, moves between two frames
// as one with samples, a cancel, Pointers' frames.
//   node tests/os/pointers-web.mjs <PointersWeb.wasm>
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const [wasm] = process.argv.slice(2);
const files = {
	'/test.wasm': wasm,
	'/os/browser.mjs': path.join(here, '../../src/helder/os/browser.mjs'),
	'/os/imports.mjs': path.join(here, '../../src/helder/os/imports.mjs'),
};
const types = { '.mjs': 'text/javascript', '.wasm': 'application/wasm' };
const page = `<!doctype html><title>PointersWeb</title><body style="margin:0">
<canvas id="c" style="width: 300px; height: 200px; display: block"></canvas>
<script type="module">
import { run } from './os/browser.mjs';
window.log = [];
document.getElementById('c').addEventListener('pointerdown', (e) => (window.lastTouch = e.pointerId));
window.started = run('test.wasm', { imports: ['os/imports.mjs'], canvas: 'c', stdout: (s) => window.log.push(s), stderr: (s) => window.log.push('stderr: ' + s) });
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
const browser = await pw.chromium.launch();
let failed = 0;
const check = (what, ok, detail) => {
	if (!ok) failed++;
	console.log(`pointers-web.mjs: ${ok ? 'ok' : 'FAIL'}: ${what}${ok ? '' : ': ' + detail}`);
};
try {
	const ctx = await browser.newContext({ deviceScaleFactor: 2, hasTouch: true });
	const p = await ctx.newPage();
	await p.goto(`http://localhost:${server.address().port}/`);
	await p.evaluate(() => window.started);
	const cdp = await ctx.newCDPSession(p);
	const settle = () => p.waitForTimeout(150);
	// the lines since the last call
	let seen = 0;
	const lines = async () => {
		await settle();
		const all = await p.evaluate(() => window.log);
		const out = all.slice(seen);
		seen = all.length;
		return out;
	};
	const touch = (type, points) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: points });
	await lines();

	// two fingers: the first down, the second, both moved, the first lifted, then the second
	await touch('touchStart', [{ x: 20, y: 15, id: 1 }]);
	await touch('touchStart', [{ x: 20, y: 15, id: 1 }, { x: 100, y: 50, id: 2 }]);
	let l = await lines();
	check('two fingers down: slots 1 and 2, buffer pixels, the first primary', l.includes('down 1 touch 40,30 primary samples 1 buttons 1') && l.includes('down 2 touch 200,100 samples 1 buttons 1'), l.join(' / '));
	check("Pointers' frame: both down, in order", l.some((s) => s.startsWith('frame 1:40,30') && s.includes(' 2:200,100')), l.join(' / '));
	await touch('touchMove', [{ x: 25, y: 15, id: 1 }, { x: 100, y: 60, id: 2 }]);
	l = await lines();
	check('both moved', l.includes('move 1 touch 50,30 primary samples 1 buttons 1') && l.includes('move 2 touch 200,120 samples 1 buttons 1'), l.join(' / '));
	await touch('touchEnd', [{ x: 25, y: 15, id: 1 }]);
	l = await lines();
	check('the first lifted', l.includes('up 1 touch 50,30 primary samples 1 buttons 0') && l.some((s) => s === 'frame 2:200,120'), l.join(' / '));
	await touch('touchEnd', []);
	l = await lines();
	check('the second lifted: none down', l.some((s) => s.startsWith('up 2 touch')) && l.includes('frame'), l.join(' / '));
	check('two fingers, no click (the first moved under the slop: still a tap)', !l.some((s) => s.startsWith('mouse-down')) || l.includes('mouse-down 1 touch'), l.join(' / '));

	// a tap: its compatibility click (Mods.TOUCH), the mouse's pointer not made of it
	await touch('touchStart', [{ x: 50, y: 50, id: 3 }]);
	await touch('touchEnd', []);
	l = await lines();
	check('a tap: down 1, up, then a click marked as a touch', l.includes('down 1 touch 100,100 primary samples 1 buttons 1') && l.includes('mouse-down 1 touch') && !l.some((s) => s.includes(' mouse ')), l.join(' / '));

	// a drag: its Scrolls while emulated
	await touch('touchStart', [{ x: 50, y: 80, id: 4 }]);
	for (let k = 1; k <= 3; k++) await touch('touchMove', [{ x: 50, y: 80 - 10 * k, id: 4 }]);
	await touch('touchEnd', []);
	l = await lines();
	check('a drag scrolls, emulated', l.some((s) => s.startsWith('scroll ')), l.join(' / '));

	// emulation off: a tap is its pointer events only
	await p.click('#c', { position: { x: 290, y: 190 } });
	await p.keyboard.press('e');
	await lines();
	await touch('touchStart', [{ x: 50, y: 50, id: 5 }]);
	await touch('touchEnd', []);
	l = await lines();
	check('emulate off: no click from a tap', l.some((s) => s.startsWith('down 1 touch')) && !l.some((s) => s.startsWith('mouse-down')), l.join(' / '));

	// moves between two frames: one event, the others its samples
	await touch('touchStart', [{ x: 10, y: 10, id: 6 }]);
	await settle();
	await p.evaluate(() => new Promise((done) => {
		// (in one task: no frame between them)
		const c = document.getElementById('c'), r = c.getBoundingClientRect();
		for (let k = 1; k <= 4; k++) c.dispatchEvent(new PointerEvent('pointermove', { pointerId: window.lastTouch ?? 0, pointerType: 'touch', clientX: r.left + 10 + k, clientY: r.top + 10, bubbles: true }));
		done();
	}));
	l = await lines();
	check('four moves in a frame: one event, its samples', l.filter((s) => s.startsWith('move 1 touch')).length === 1 && l.some((s) => s.startsWith('move 1 touch 28,20 primary samples 4')), l.join(' / '));
	await touch('touchCancel', []);
	const c = await lines();
	check('a cancel', c.some((s) => s.startsWith('cancel 1 touch')), c.join(' / '));

	// a pen: a pointer of its own (slot 1), without the mouse's events
	await cdp.send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 30, y: 30, pointerType: 'pen' });
	await cdp.send('Input.dispatchMouseEvent', { type: 'mousePressed', x: 30, y: 30, button: 'left', buttons: 1, clickCount: 1, pointerType: 'pen' });
	await cdp.send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 40, y: 30, button: 'left', buttons: 1, pointerType: 'pen' });
	await cdp.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: 40, y: 30, button: 'left', buttons: 0, clickCount: 1, pointerType: 'pen' });
	l = await lines();
	check('a pen: its own slot, no mouse events', l.includes('down 1 pen 60,60 primary samples 1 buttons 1') && l.some((s) => s.startsWith('up 1 pen 80,60')) && !l.some((s) => s.startsWith('mouse-')), l.join(' / '));

	// the mouse: slot 0 after its own events, its buttons
	await p.mouse.move(150, 100);
	await p.mouse.down();
	await p.mouse.move(160, 100);
	await p.mouse.up();
	l = await lines();
	check('the mouse: slot 0, after its MouseDown', l.indexOf('mouse-down 1') >= 0 && l.indexOf('down 0 mouse 300,200 primary samples 1 buttons 1') > l.indexOf('mouse-down 1') && l.includes('move 0 mouse 320,200 primary samples 1 buttons 1') && l.some((s) => s.startsWith('up 0 mouse 320,200')), l.join(' / '));
	const errors = (await p.evaluate(() => window.log)).filter((s) => s.startsWith('stderr'));
	check('no errors', errors.length === 0, errors.join(' / '));
} finally {
	await browser.close();
	server.close();
}
if (failed > 0) {
	console.log(`pointers-web.mjs: ${failed} FAILED`);
	process.exit(1);
}
console.log('pointers-web.mjs: ok');
