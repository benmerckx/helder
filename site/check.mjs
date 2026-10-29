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
	for (const id of play) {
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
	}
	// (a game full screen and expanded at a phone's size, a touch drag still the game's: golf's shot, its strokes in ui's accessibility mirror)
	if (play.includes('golf')) await phone(page, shots);
	check(errors.length === 0, `no console errors${errors.length ? ': ' + errors.join('\n') : ''}`);
} finally {
	await browser.close();
	server.close();
}
if (failures) process.exit(1);

// golf at 390x844: full screen (the Fullscreen API) then expanded (as on an
// iPhone, without element full screen): the canvas filling the screen at
// the device's pixels, a touch drag from the ball shooting (STROKES 1 in the
// mirror) without scrolling the page; screenshots of both when asked
async function phone(page, shots) {
	await page.setViewportSize({ width: 390, height: 844 });
	const stage = page.locator('#golf .stage'), canvas = page.locator('#play-golf canvas');
	await stage.scrollIntoViewIfNeeded();
	await page.locator('#golf button.full').click();
	await page.waitForTimeout(1500);
	const full = await page.evaluate(() => {
		const c = document.querySelector('#play-golf canvas'), s = document.querySelector('#golf .stage');
		return { el: document.fullscreenElement === s, w: c.clientWidth, h: c.clientHeight, bw: c.width, bh: c.height, dpr: devicePixelRatio };
	});
	check(full.el && full.w === 390 && full.h === 844, `golf full screen: the stage the full screen element, its canvas ${full.w}x${full.h}`);
	check(full.bw === Math.round(full.w * full.dpr) && full.bh === Math.round(full.h * full.dpr), `golf full screen: the canvas's buffer ${full.bw}x${full.bh} (its size times ${full.dpr})`);
	if (shots) await page.screenshot({ path: path.join(shots, 'golf-fullscreen.png') });
	await page.locator('#golf button.exit').click();
	await page.waitForTimeout(800);
	check(await page.evaluate(() => !document.fullscreenElement && !document.querySelector('#golf .stage.expanded')), 'golf full screen: left by Exit');
	// (as on an iPhone: no element full screen, so expanded over the page)
	await page.evaluate(() => {
		for (const k of ['fullscreenEnabled', 'webkitFullscreenEnabled']) Object.defineProperty(document, k, { get: () => false, configurable: true });
	});
	await page.locator('#golf button.full').click();
	await page.waitForTimeout(1500);
	const box = await canvas.boundingBox();
	const ex = await page.evaluate(() => {
		const c = document.querySelector('#play-golf canvas');
		return { expanded: !!document.querySelector('#golf .stage.expanded'), full: !!document.fullscreenElement, touch: getComputedStyle(c).touchAction,
			bw: c.width, scroll: scrollY, text: c.textContent };
	});
	check(ex.expanded && !ex.full && Math.round(box.width) === 390 && Math.round(box.height) === 844, `golf expanded: over the viewport, ${Math.round(box.width)}x${Math.round(box.height)}`);
	check(ex.touch === 'none', `golf expanded: the canvas's touch-action ${ex.touch}`);
	check(/STROKES0/.test(ex.text), 'golf expanded: no stroke yet (the mirror)');
	if (shots) await page.screenshot({ path: path.join(shots, 'golf-expanded.png') });
	// (a finger: from the ball, back down, let go; the DevTools protocol's touches)
	const cdp = await page.context().newCDPSession(page);
	const at = (x, y) => [{ x, y, id: 1, radiusX: 4, radiusY: 4, force: 1 }];
	const x = box.x + box.width / 2, y0 = box.y + box.height * 597 / 844;
	await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: at(x, y0) });
	for (let i = 1; i <= 12; i++) {
		await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: at(x + i * 0.3, y0 + i * 9) });
		await page.waitForTimeout(25);
	}
	if (shots) await page.screenshot({ path: path.join(shots, 'golf-expanded-aim.png') });
	await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
	await page.waitForTimeout(2500);
	const after = await page.evaluate(() => ({ text: document.querySelector('#play-golf canvas').textContent, scroll: scrollY }));
	check(/STROKES1/.test(after.text), 'golf expanded: a touch drag from the ball shot it (STROKES 1)');
	check(after.scroll === ex.scroll, `golf expanded: the page did not scroll (${ex.scroll}, ${after.scroll})`);
	if (shots) await page.screenshot({ path: path.join(shots, 'golf-expanded-rolling.png') });
	await page.locator('#golf button.exit').click();
	await page.waitForTimeout(500);
	check(await page.evaluate(() => !document.querySelector('#golf .stage.expanded') && !document.documentElement.classList.contains('playing')), 'golf expanded: left by Exit');
	await page.setViewportSize({ width: 1280, height: 900 });
}
