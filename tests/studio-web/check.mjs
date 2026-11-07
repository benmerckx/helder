// helder studio in the browser (bun run test studio-web): the page that
// apps/studio/web/build.mjs writes, in headless Chromium on WebGPU
// (SwiftShader), driven by real input (Playwright's mouse, keyboard and
// touches, CDP's two-finger touches), its own module's canvas read back
// (host.gfx.readPixels: what the studio drew, the preview's frames
// composited) against goldens:
//
// - desktop (1180 x 740): the welcome's Todo opened (an example bundled
//   with the page: OPFS, the preview host started in its worker), all four
//   screens shown, a screen zoomed into, its title clicked and selected
//   (Ui.getTree through the worker), its colour changed in the inspector:
//   a live literal patched in the preview host, the next frames show it
//   (frames counted, the title's pixels red), the file saved in OPFS; a
//   structural edit (a padding) needs the compiler's worker: built when the
//   page has one, else said;
// - phone (390 x 844, touch): the same project in the compact layout, a
//   screen tapped, the inspector a bottom sheet, the title tapped, its
//   colour patched, a pinch zooming the canvas, the screens' drawer;
// - 50 screens (tests/story/host/host.mjs project): opened, the time to
//   every screen shown, the memory (the studio's module, the preview's,
//   the page's JavaScript), the frames each screen drew.
//
//   node tests/studio-web/check.mjs <site> <out> [--bless]
//
// Goldens (tests/studio-web/*.png): the overview and the zoomed state at
// both widths; BLESS writes them. The numbers go to <out>/results.md, the
// page's screenshots to <out>.
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try {
	pw = require('playwright');
} catch {
	pw = require(path.join(process.execPath, '../../lib/node_modules/playwright'));
}
const here = path.dirname(fileURLToPath(import.meta.url));
const [site, out] = process.argv.slice(2);
const BLESS = process.argv.includes('--bless') || !!process.env.BLESS;
await mkdir(out, { recursive: true });
const types = { '.mjs': 'text/javascript', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.html': 'text/html', '.ttf': 'font/ttf', '.png': 'image/png' };
const server = createServer(async (req, res) => {
	let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
	if (p === '/') p = '/index.html';
	const file = p.startsWith('/goldens/') ? path.join(here, p.slice(9)) : path.join(site, p);
	try {
		const b = await readFile(file);
		res.writeHead(200, { 'content-type': types[path.extname(p)] ?? 'application/octet-stream' });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
}).listen(0);
const base = `http://127.0.0.1:${server.address().port}/`;
const browser = await pw.chromium.launch({ args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader', '--enable-precise-memory-info'] });
console.log(`studio-web: chromium ${browser.version()}`);

let failures = 0, checks = 0;
const numbers = [];
function check(ok, what) {
	checks++;
	if (ok) console.log(`studio-web: ok: ${what}`);
	else {
		failures++;
		console.log(`studio-web: FAIL: ${what}`);
	}
}

async function page(viewport, touch) {
	const ctx = await browser.newContext({ viewport, hasTouch: touch, isMobile: touch, deviceScaleFactor: 1 });
	const pg = await ctx.newPage();
	pg.on('pageerror', (e) => console.log('studio-web: page error: ' + e.message));
	pg.on('console', (m) => /error|exit|stderr/i.test(m.text()) && console.log('studio-web: console: ' + m.text().slice(0, 400)));
	await pg.goto(base);
	await ready(pg);
	return pg;
}

const ready = (pg) => pg.waitForFunction(() => window.studioWeb?.ready || window.studioWeb?.error, null, { timeout: 60000 });
const events = (pg) => pg.evaluate(() => window.studioWeb.events);
async function event(pg, name, pred = () => true, timeout = 30000) {
	const t0 = Date.now();
	while (Date.now() - t0 < timeout) {
		const e = (await events(pg)).filter((x) => x.event === name).find(pred);
		if (e) return e;
		await pg.waitForTimeout(50);
	}
	return null;
}
const lastFrame = async (pg) => (await events(pg)).reduce((n, e) => Math.max(n, e.frame ?? 0), 0);

// a control of the studio by its accessible name (its ARIA mirror in the canvas), activated as a screen reader would
async function press(pg, label) {
	return pg.evaluate((label) => {
		const e = [...document.querySelectorAll('#studio [role=button]')].find((x) => x.getAttribute('aria-label') === label);
		if (!e) return false;
		e.click();
		return true;
	}, label);
}

async function openExample(pg, label) {
	check(await press(pg, label), `the welcome lists ${label}`);
	await pg.waitForURL(/project=/, { timeout: 30000 });
	await ready(pg);
	return event(pg, 'all-shown', () => true, 60000);
}

// the studio's canvas as it drew it: against a golden (or written as it, blessing)
async function golden(pg, name) {
	const r = await pg.evaluate(async ({ name, bless }) => {
		const h = window.studioWeb.host;
		const p = h.gfx.readPixels();
		h.os.redraw();
		const px = await p;
		if (bless) {
			const c = new OffscreenCanvas(px.width, px.height);
			c.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(px.data), px.width, px.height), 0, 0);
			const b = new Uint8Array(await (await c.convertToBlob({ type: 'image/png' })).arrayBuffer());
			let s = '';
			for (const x of b) s += String.fromCharCode(x);
			return { png: btoa(s) };
		}
		const res = await fetch('/goldens/' + name + '.png');
		if (!res.ok) return { text: 'no golden ' + name + '.png (BLESS=1 writes it)' };
		const img = await createImageBitmap(await res.blob(), { colorSpaceConversion: 'none', premultiplyAlpha: 'none' });
		const c = new OffscreenCanvas(img.width, img.height).getContext('2d');
		c.drawImage(img, 0, 0);
		const g = c.getImageData(0, 0, img.width, img.height).data;
		if (img.width !== px.width || img.height !== px.height) return { text: `${px.width}x${px.height}, the golden ${img.width}x${img.height}` };
		let off = 0, most = 0;
		for (let i = 0; i < g.length; i += 4) {
			const d = Math.max(Math.abs(g[i] - px.data[i]), Math.abs(g[i + 1] - px.data[i + 1]), Math.abs(g[i + 2] - px.data[i + 2]));
			if (d > 24) off++;
			most = Math.max(most, d);
		}
		const n = px.width * px.height;
		return { ok: off <= n * 0.005, text: `${off} of ${n} pixels off by more than 24 (at most ${most})` };
	}, { name, bless: BLESS });
	await pg.screenshot({ path: path.join(out, name + '.png') });
	if (r.png) {
		await writeFile(path.join(here, name + '.png'), Buffer.from(r.png, 'base64'));
		console.log(`studio-web: ${name}.png blessed`);
	} else check(r.ok, `${name}: ${r.text}`);
}

// a pixel of the studio's canvas
async function pixel(pg, x, y) {
	return pg.evaluate(async ([x, y]) => {
		const h = window.studioWeb.host;
		const p = h.gfx.readPixels();
		h.os.redraw();
		const d = await p;
		const i = (y * d.width + x) * 4;
		return [d.data[i], d.data[i + 1], d.data[i + 2]];
	}, [x, y]);
}
const red = (c) => c[0] > 200 && c[1] < 110 && c[2] < 110;

// the colour typed into the inspector's colour field (at x, y): a live literal patched, its frames
async function recolour(pg, x, y, tap) {
	const before = await lastFrame(pg);
	if (tap) await pg.touchscreen.tap(x, y);
	else await pg.mouse.click(x, y);
	await pg.waitForTimeout(300);
	await pg.keyboard.press('Control+a');
	await pg.keyboard.type('#ef4444');
	await pg.keyboard.press('Enter');
	const patched = await event(pg, 'patched', (e) => e.frame >= before);
	const shown = await event(pg, 'patch-shown', (e) => e.frame >= before);
	check(patched && patched.patches.length === 1 && patched.patches[0].source === '"#ef4444"', 'the colour a live literal patch, nothing built: ' + JSON.stringify(patched?.patches));
	check(shown && shown.frames <= 3, `the patch shown in the preview's next frames: ${shown?.ms} ms, ${shown?.frames} studio frame(s)`);
	const saved = await pg.evaluate(async () => {
		await window.studioWeb.saved?.();
		const d = await (await (await navigator.storage.getDirectory()).getDirectoryHandle('projects')).getDirectoryHandle(window.studioWeb.project);
		return (await (await d.getFileHandle('Todo.hx')).getFile()).text();
	});
	check(saved.includes('color="#ef4444"'), 'Todo.hx saved in OPFS with the colour');
	return shown;
}

// ---- desktop
{
	const pg = await page({ width: 1180, height: 740 }, false);
	await pg.screenshot({ path: path.join(out, 'desktop-welcome.png') });
	const shown = await openExample(pg, 'Todo');
	const by = await pg.evaluate(() => window.studioWeb.framesByScreen);
	check(shown && shown.screens === 4 && Object.keys(by).length === 4, `all 4 screens shown (${shown?.ms} ms after opening, frames by screen ${JSON.stringify(by)})`);
	const started = await pg.evaluate(() => window.studioWeb.started);
	numbers.push(['todo (4 screens)', 'desktop', started, shown]);
	await pg.waitForTimeout(400);
	await golden(pg, 'desktop-overview');
	await pg.mouse.click(700, 210);
	await pg.waitForTimeout(1600);
	await golden(pg, 'desktop-zoomed');
	await pg.mouse.click(560, 110);
	const sel = await event(pg, 'selected');
	check(sel && sel.tag === 'text' && sel.screen === 'Todo/Three items' && sel.rect.join() === '24,24,432,35', 'the title selected: ' + JSON.stringify(sel && [sel.screen, sel.tag, sel.rect]));
	await pg.waitForTimeout(400);
	await pg.screenshot({ path: path.join(out, 'desktop-selected.png') });
	const p = await recolour(pg, 1080, 262, false);
	numbers.push(['desktop patch', p]);
	check(red(await pixel(pg, 380, 122)), 'the title red in the studio\'s canvas (the preview\'s frame, composited)');
	await pg.screenshot({ path: path.join(out, 'desktop-colored.png') });
	// a structural edit: the compiler's worker builds it, or the studio says it cannot yet
	const compiler = await pg.evaluate(() => !!window.studioWeb.compiler);
	const before = await lastFrame(pg);
	await pg.mouse.click(1080, 140);
	await pg.waitForTimeout(200);
	await pg.keyboard.type('20');
	await pg.keyboard.press('Enter');
	const built = await event(pg, 'built', (e) => e.frame >= before, compiler ? 120000 : 10000);
	if (compiler) check(built && built.ok, `a padding added: built by the compiler's worker in ${built?.ms} ms, the screens reloaded`);
	else {
		check(built && !built.ok, 'a padding added: saved, not built (no compiler worker on this page yet)');
		console.log('studio-web: structural edits: skipped, the page has no compiler worker (helder.compiler.web)');
	}
	await pg.context().close();
}

// ---- phone (touch, compact: the inspector a bottom sheet, the screens' list a drawer)
{
	const pg = await page({ width: 390, height: 844 }, true);
	const shown = await openExample(pg, 'Todo');
	check(shown && shown.screens === 4, `phone: all 4 screens shown (${shown?.ms} ms)`);
	await pg.waitForTimeout(400);
	await golden(pg, 'phone-overview');
	await pg.touchscreen.tap(195, 320);
	await pg.waitForTimeout(1600);
	await golden(pg, 'phone-zoomed');
	await pg.touchscreen.tap(60, 120);
	const sel = await event(pg, 'selected');
	check(sel && sel.tag === 'text' && sel.screen === 'Todo/Three items', 'phone: the title tapped and selected: ' + JSON.stringify(sel && [sel.screen, sel.tag, sel.rect]));
	await pg.waitForTimeout(500);
	await pg.screenshot({ path: path.join(out, 'phone-selected.png') });
	const p = await recolour(pg, 110, 782, true);
	numbers.push(['phone patch', p]);
	check(red(await pixel(pg, 60, 120)), 'phone: the title red in the studio\'s canvas');
	// two fingers apart over the canvas: zoomed in
	const cdp = await pg.context().newCDPSession(pg);
	const touch = (type, points) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: points });
	const at = (d) => [{ x: 195 - d, y: 300, id: 1 }, { x: 195 + d, y: 300, id: 2 }];
	await touch('touchStart', at(30));
	for (let d = 34; d <= 90; d += 4) {
		await touch('touchMove', at(d));
		await pg.waitForTimeout(16);
	}
	await touch('touchEnd', []);
	const pinch = await event(pg, 'pinched', () => true, 5000);
	check(pinch && pinch.k > 1, `phone: a pinch zooms the canvas in (k ${pinch?.k})`);
	await pg.waitForTimeout(300);
	await pg.screenshot({ path: path.join(out, 'phone-pinched.png') });
	check(await press(pg, 'Screens'), 'phone: the screens\' drawer opened from the header');
	await pg.waitForTimeout(600);
	await pg.screenshot({ path: path.join(out, 'phone-drawer.png') });
	check(await press(pg, 'Todo/Done'), 'phone: a screen chosen in the drawer');
	await pg.waitForTimeout(1600);
	await pg.screenshot({ path: path.join(out, 'phone-done.png') });
	await pg.context().close();
}

// ---- 50 screens
{
	const pg = await page({ width: 1180, height: 740 }, false);
	const t0 = Date.now();
	const shown = await openExample(pg, '50 screens');
	const wall = Date.now() - t0;
	const by = await pg.evaluate(() => window.studioWeb.framesByScreen);
	check(shown && shown.screens === 50 && Object.keys(by).length === 50, `50 screens: all shown, ${shown?.ms} ms after opening (${wall} ms from the welcome's click, the page loaded again)`);
	const stats = await pg.evaluate(() => window.studioWeb.stats());
	const started = await pg.evaluate(() => window.studioWeb.started);
	numbers.push(['50 screens', stats, started, shown, wall]);
	await pg.waitForTimeout(300);
	await pg.screenshot({ path: path.join(out, 'screens50-overview.png') });
	// one zoomed into: the others' frames stop (only the screens in view draw)
	const before = await pg.evaluate(() => ({ ...window.studioWeb.framesByScreen }));
	await pg.mouse.click(Number(process.env.S50_X ?? 330), Number(process.env.S50_Y ?? 150));
	await pg.waitForTimeout(2000);
	const after = await pg.evaluate(() => window.studioWeb.framesByScreen);
	const drew = Object.keys(after).filter((k) => after[k] !== before[k]).length;
	check(drew <= 10, `50 screens: one zoomed into, ${drew} screen(s) drew since (the ones in view)`);
	await pg.screenshot({ path: path.join(out, 'screens50-zoomed.png') });
	await pg.context().close();
}

await browser.close();
server.close();

// ---- the numbers
const mb = (b) => (b / 1048576).toFixed(1) + ' MB';
const lines = ['| | |', '|---|---|'];
for (const n of numbers) {
	if (n[0] === 'todo (4 screens)') lines.push(`| todo, 4 screens: the preview's worker started (its module instantiated, main run) | ${Math.round(n[2]?.ms)} ms (${n[2]?.backend}) |`, `| todo: the project opened to every screen shown | ${n[3]?.ms} ms |`);
	else if (n[0] === '50 screens') lines.push(`| 50 screens: the project opened to every screen shown | ${n[3]?.ms} ms (${n[4]} ms from the click, the page loaded again) |`,
		`| 50 screens: memory: the preview's module, the studio's, the page's JavaScript | ${mb(n[1].preview)}, ${mb(n[1].studio)}, ${mb(n[1].js)} |`);
	else lines.push(`| ${n[0]}: an inspector's colour to the preview's frame (a live literal) | ${n[1]?.ms} ms, ${n[1]?.frames} studio frame(s) |`);
}
const table = lines.join('\n');
console.log(table);
await writeFile(path.join(out, 'results.md'), table + '\n');
console.log(`studio-web: ${checks} checks, ${failures ? failures + ' FAILED' : 'ok'}`);
process.exit(failures ? 1 : 0);
