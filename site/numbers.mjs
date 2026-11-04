// The demos' numbers (bun run site:numbers, after bun run site), measured in
// headless Chromium (Playwright; SwiftShader: software rendering, not a
// GPU's): each example with a page.json played on its page, once per scene
// it names (page.json's numbers: an argument after the data folder's), for
// SECONDS; its program prints `stats: {...}` lines (firstFrameMs,
// downloadBytes, textureBytes, p50Ms, p99Ms), the last of which is kept.
// Written to bin/site/numbers.json, which the pages read (numbers.js): per
// <id>[.<scene>] the first frame (ms), the download and GPU textures (MB),
// the frame times' p50 and p99 (ms), and the graphics API it drew with.
//
//   node site/numbers.mjs [ids...]
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(root, 'bin/site');
const SECONDS = +(process.env.NUMBERS_SECONDS ?? 12);
const site = JSON.parse(fs.readFileSync(path.join(root, 'bin/site-build/examples.json'), 'utf8'));
const ids = process.argv.slice(2);
const paged = site.examples.filter((e) => e.page && e.demo && (!ids.length || ids.includes(e.id)));

const types = { '.mjs': 'text/javascript', '.js': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html', '.json': 'application/json' };
const server = createServer(async (req, res) => {
	const p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
	try {
		const b = await readFile(path.join(dir, p.endsWith('/') ? p + 'index.html' : p));
		res.writeHead(200, { 'content-type': types[path.extname(p)] ?? 'application/octet-stream' });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
}).listen(0);
const url = `http://localhost:${server.address().port}/`;
const out = path.join(dir, 'numbers.json');
const numbers = fs.existsSync(out) ? JSON.parse(fs.readFileSync(out, 'utf8')) : {};
const mb = (b) => Math.round(b / 104857.6) / 10;

const browser = await pw.chromium.launch({ args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'] });
try {
	for (const e of paged) {
		for (const scene of e.page.numbers.length ? e.page.numbers : ['']) {
			const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
			let last = null;
			page.on('console', (m) => {
				const t = m.text();
				if (t.startsWith('stats: ')) try { last = JSON.parse(t.slice(7)); } catch {}
			});
			// (a scene: the island's arguments with it after the data folder's)
			await page.goto(`${url}${e.id}.html`);
			if (scene) await page.evaluate(([id, s]) => {
				const el = document.getElementById('play-' + id);
				el.dataset.args = JSON.stringify([...JSON.parse(el.dataset.args || '[]'), s]);
			}, [e.id, scene]);
			const t0 = Date.now();
			await page.locator(`#play-${e.id} button.play`).click();
			await page.waitForFunction((id) => {
				const el = document.getElementById('play-' + id);
				return el.hasAttribute('data-hydrated') || el.hasAttribute('data-error');
			}, e.id, { timeout: 120000 });
			const gfx = await page.locator(`#play-${e.id}`).getAttribute('data-gfx');
			await page.waitForTimeout(SECONDS * 1000);
			const key = e.id + (scene ? '.' + scene : '');
			numbers[key] = last ? { firstFrameMs: last.firstFrameMs, downloadMB: mb(last.downloadBytes), memoryMB: mb(last.textureBytes), p50Ms: last.p50Ms,
				p99Ms: last.p99Ms, gfx, measured: new Date().toISOString().slice(0, 10), software: true } : null;
			console.log(`${key.padEnd(28)} ${last ? JSON.stringify(numbers[key]) : 'no stats line'} (${((Date.now() - t0) / 1000).toFixed(0)} s)`);
			await page.close();
		}
	}
} finally {
	await browser.close();
	server.close();
}
fs.writeFileSync(out, JSON.stringify(numbers, null, '\t') + '\n');
