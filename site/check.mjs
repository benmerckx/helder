// The site's check (bun run site:check, after bun run site), in headless
// Chromium (Playwright): bin/site served, every example a card, then the
// Play button of every demo pressed (or of the ids given): each started (data-hydrated, the
// graphics API it draws with in data-gfx), its canvas drawn (it looks
// different from before; a sound only started), no console errors. With a
// directory, the page's screenshots at a phone's width and a desktop's are
// written there.
//
//   node site/check.mjs [screenshots dir] [ids to play...]   (default: every demo)
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(root, 'bin/site');
const [shots, ...ids] = process.argv.slice(2);
const site = JSON.parse(fs.readFileSync(path.join(root, 'bin/site-build/examples.json'), 'utf8'));
const play = ids.length ? ids : site.examples.filter((e) => e.demo).map((e) => e.id);

const types = { '.mjs': 'text/javascript', '.js': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html', '.json': 'application/json' };
const server = createServer(async (req, res) => {
	const p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
	try {
		const b = await readFile(path.join(dir, p.endsWith('/') ? p + 'index.html' : p));
		res.writeHead(200, { 'content-type': types[path.extname(p)] ?? (p.endsWith('/') ? 'text/html' : 'application/octet-stream') });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
}).listen(0);
const url = `http://localhost:${server.address().port}/`;

const browser = await pw.chromium.launch({ args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'] });
let failures = 0;
const check = (ok, what) => {
	console.log(`${ok ? 'PASS' : 'FAIL'} ${what}`);
	if (!ok) failures++;
};
try {
	const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
	const errors = [];
	page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
	page.on('pageerror', (e) => errors.push(String(e)));
	await page.goto(url);
	const cards = await page.locator('article.card').count();
	check(cards === site.examples.length, `${cards} cards, ${site.examples.length} examples`);
	const buttons = await page.locator('button.play').count();
	check(buttons === site.examples.filter((e) => e.demo).length, `${buttons} Play buttons`);
	for (const e of site.examples) {
		const card = page.locator(`#${e.id}`);
		const title = await card.locator('h2').textContent();
		if (title !== e.title) check(false, `${e.id}'s title: ${title}`);
	}
	if (shots) {
		await mkdir(shots, { recursive: true });
		await page.screenshot({ path: path.join(shots, 'site-desktop.png') });
		await page.setViewportSize({ width: 390, height: 844 });
		await page.screenshot({ path: path.join(shots, 'site-phone.png') });
		await page.screenshot({ path: path.join(shots, 'site-phone-full.png'), fullPage: true });
		await page.setViewportSize({ width: 1280, height: 900 });
	}
	// (each demo alone in the page, loaded again: the heavy ones, a million
	// particles on a software GPU, would slow the next ones' checks)
	async function start(id) {
		await page.goto(url);
		const island = page.locator(`#play-${id}`);
		await island.scrollIntoViewIfNeeded();
		await island.locator('button.play').click();
		await page.waitForFunction((id) => document.getElementById('play-' + id).hasAttribute('data-hydrated'), id, { timeout: 60000 });
	}
	for (const id of play) {
		await page.goto(url);
		const island = page.locator(`#play-${id}`), canvas = island.locator('canvas');
		await island.scrollIntoViewIfNeeded();
		// (a sound has no canvas: started, nothing drawn)
		const drawn = (await canvas.count()) > 0;
		const before = drawn ? await canvas.screenshot() : null;
		await island.locator('button.play').click();
		await page.waitForFunction((id) => {
			const el = document.getElementById('play-' + id);
			return el.hasAttribute('data-hydrated') || el.hasAttribute('data-error');
		}, id, { timeout: 60000 });
		const error = await island.getAttribute('data-error'), gfx = await island.getAttribute('data-gfx');
		check(error === null, `${id} started${error ? ': ' + error : ''}`);
		if (!drawn) continue;
		check(!!gfx, `${id} draws with ${gfx}`);
		await page.waitForTimeout(1500);
		await island.scrollIntoViewIfNeeded();
		const after = await canvas.screenshot();
		check(!before.equals(after), `${id}'s canvas drawn`);
		if (shots) {
			await page.screenshot({ path: path.join(shots, `site-desktop-${id}.png`) });
			await page.setViewportSize({ width: 390, height: 844 });
			await page.waitForTimeout(800);
			await island.scrollIntoViewIfNeeded();
			await page.screenshot({ path: path.join(shots, `site-phone-${id}.png`) });
			await page.setViewportSize({ width: 1280, height: 900 });
		}
		// (an example of fetched data, heavy: stopped once out of view, data-stop="offscreen")
		if (site.examples.find((x) => x.id === id)?.args?.length) {
			await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
			await page.waitForFunction((id) => document.getElementById('play-' + id).hasAttribute('data-stopped'), id, { timeout: 30000 });
			check(true, `${id} stopped out of view`);
		}
	}
	// (a demo full screen and expanded at a phone's size: planets, ui's markup with a <Scene> in it)
	if (play.includes('planets')) {
		await start('planets');
		await phone(page, shots, 'planets');
	}
	check(errors.length === 0, `no console errors${errors.length ? ': ' + errors.join('\n') : ''}`);
} finally {
	await browser.close();
	server.close();
}
if (failures) process.exit(1);

// a demo at 390x844: full screen (the Fullscreen API) then expanded (as on
// an iPhone, without element full screen): the canvas filling the screen
// at the device's pixels, its touches the demo's (touch-action none), the
// page not scrolled; screenshots of both when asked
async function phone(page, shots, id) {
	await page.setViewportSize({ width: 390, height: 844 });
	const stage = page.locator(`#${id} .stage`), canvas = page.locator(`#play-${id} canvas`);
	await stage.scrollIntoViewIfNeeded();
	await page.locator(`#${id} button.full`).click();
	await page.waitForTimeout(1500);
	const full = await page.evaluate((id) => {
		const c = document.querySelector(`#play-${id} canvas`), s = document.querySelector(`#${id} .stage`);
		return { el: document.fullscreenElement === s, w: c.clientWidth, h: c.clientHeight, bw: c.width, bh: c.height, dpr: devicePixelRatio };
	}, id);
	check(full.el && full.w === 390 && full.h === 844, `${id} full screen: the stage the full screen element, its canvas ${full.w}x${full.h}`);
	check(full.bw === Math.round(full.w * full.dpr) && full.bh === Math.round(full.h * full.dpr), `${id} full screen: the canvas's buffer ${full.bw}x${full.bh} (its size times ${full.dpr})`);
	if (shots) await page.screenshot({ path: path.join(shots, `${id}-fullscreen.png`) });
	await page.locator(`#${id} button.exit`).click();
	await page.waitForTimeout(800);
	check(await page.evaluate((id) => !document.fullscreenElement && !document.querySelector(`#${id} .stage.expanded`), id), `${id} full screen: left by Exit`);
	// (as on an iPhone: no element full screen, so expanded over the page)
	await page.evaluate(() => {
		for (const k of ['fullscreenEnabled', 'webkitFullscreenEnabled']) Object.defineProperty(document, k, { get: () => false, configurable: true });
	});
	await page.locator(`#${id} button.full`).click();
	await page.waitForTimeout(1500);
	const box = await canvas.boundingBox();
	const ex = await page.evaluate((id) => {
		const c = document.querySelector(`#play-${id} canvas`);
		return { expanded: !!document.querySelector(`#${id} .stage.expanded`), full: !!document.fullscreenElement, touch: getComputedStyle(c).touchAction, scroll: scrollY };
	}, id);
	check(ex.expanded && !ex.full && Math.round(box.width) === 390 && Math.round(box.height) === 844, `${id} expanded: over the viewport, ${Math.round(box.width)}x${Math.round(box.height)}`);
	check(ex.touch === 'none', `${id} expanded: the canvas's touch-action ${ex.touch}`);
	// (a finger dragged over it: the demo's, the page not scrolled; the DevTools protocol's touches)
	const cdp = await page.context().newCDPSession(page);
	const at = (x, y) => [{ x, y, id: 1, radiusX: 4, radiusY: 4, force: 1 }];
	const x = box.x + box.width / 2, y0 = box.y + box.height / 2;
	await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: at(x, y0) });
	for (let i = 1; i <= 12; i++) {
		await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: at(x, y0 + i * 9) });
		await page.waitForTimeout(25);
	}
	await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
	await page.waitForTimeout(500);
	check(await page.evaluate(() => scrollY) === ex.scroll, `${id} expanded: a touch drag did not scroll the page`);
	if (shots) await page.screenshot({ path: path.join(shots, `${id}-expanded.png`) });
	await page.locator(`#${id} button.exit`).click();
	await page.waitForTimeout(500);
	check(await page.evaluate((id) => !document.querySelector(`#${id} .stage.expanded`) && !document.documentElement.classList.contains('playing'), id), `${id} expanded: left by Exit`);
	await page.setViewportSize({ width: 1280, height: 900 });
}
