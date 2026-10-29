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
	check(errors.length === 0, `no console errors${errors.length ? ': ' + errors.join('\n') : ''}`);
} finally {
	await browser.close();
	server.close();
}
if (failures) process.exit(1);
