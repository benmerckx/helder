// helder.web in headless Chromium (npm test -- web): the DOM renderer's checks
// (DomTest.hx, domtest.js), then the demo page (examples:
// DemoPage's index.html, DemoBundle's islands.js, Counter's counter.js,
// lab.wasm, cube.wasm, counter-ui.wasm) served as a static site with src/helder/web/loader.js
// and the packages' browser.mjs and imports.mjs:
// - the islands hydrate without making a node again (every node of the
//   page's islands, taken before the loader runs, still there, in order;
//   only the starts of comment pairs are removed),
//   and react afterwards (clicks, typing, a list, a Show, an attribute, a
//   style, SVG);
// - the island whose markup differs on the client is rendered again, with
//   the debug build's warning;
// - a JavaScript island calls lab.wasm's exports (LabExports: numbers,
//   strings, 64 KB of bytes each way);
// - the WebAssembly island (gfx's cube) is not fetched before it scrolls
//   into view, then draws (WebGPU or WebGL2 on SwiftShader);
// - ui's counter as a page's <Surface> (counter-ui.wasm, its own root a
//   <Surface>) runs on the canvas the page sizes, and follows its size;
// then prints the sizes of counter.js (a small island alone) and loader.js.
//   node tests/web/web.mjs <dir: domtest.js, demo/>
// (Playwright from npm, with Chromium: npx playwright install chromium)
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const [dir] = process.argv.slice(2);
if (!dir) {
	console.error('usage: node web.mjs <dir>');
	process.exit(2);
}
const CHROMIUM_ARGS = ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'];
const pkg = (p) => path.join(here, '../../src/helder', p);
const files = {
	'/loader.js': pkg('web/loader.js'),
	'/web/imports.mjs': pkg('web/imports.mjs'),
	'/os/browser.mjs': pkg('os/browser.mjs'),
	'/os/imports.mjs': pkg('os/imports.mjs'),
	'/gfx/imports.mjs': pkg('gfx/imports.mjs'),
	'/text/imports.mjs': pkg('text/imports.mjs'),
	'/ui/imports.mjs': pkg('ui/imports.mjs'),
	'/fonts/DejaVuSans.ttf': ['/usr/share/fonts/truetype/dejavu', '/usr/share/fonts/TTF', '/usr/share/fonts/dejavu'].map((d) => path.join(d, 'DejaVuSans.ttf')).find((f) => existsSync(f)),
	'/domtest.js': path.join(dir, 'domtest.js'),
	'/domtest.html': null,
};
const types = { '.mjs': 'text/javascript', '.js': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html' };
const requested = [];
const server = createServer(async (req, res) => {
	const p = new URL(req.url, 'http://x').pathname;
	requested.push(p);
	try {
		const b = p === '/domtest.html' ? Buffer.from('<!doctype html><title>DomTest</title><body><script src="domtest.js"></script>')
			: await readFile(p in files ? files[p] : path.join(dir, 'demo', p === '/' ? 'index.html' : p));
		res.writeHead(200, { 'content-type': types[path.extname(p)] ?? 'text/html' });
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
function check(what, ok, detail) {
	if (!ok) failed++;
	console.log(`web.mjs: ${ok ? 'ok' : 'FAIL'}: ${what}${!ok && detail !== undefined ? ': ' + JSON.stringify(detail) : ''}`);
}

// the DOM renderer
{
	const p = await browser.newPage();
	const errors = [];
	p.on('pageerror', (e) => errors.push(e.message));
	await p.goto(url + 'domtest.html');
	const r = await p.evaluate(() => window.domTest);
	check(`DomTest: ${r?.checks} checks`, r && r.failed.length === 0 && errors.length === 0, r ? r.failed.concat(errors) : errors);
	const surface = await p.waitForFunction(() => window.domSurface, null, { timeout: 5000 }).then((h) => h.jsonValue()).catch(() => null);
	check('DomTest: a DOM <Surface> starts its module on its canvas', surface && surface.url.endsWith('/app.wasm') && surface.canvas && surface.fonts[0].endsWith('f.ttf')
		&& surface.imports.includes('ui/imports.mjs'), surface);
	await p.close();
}

// the demo page
{
	const p = await browser.newPage({ viewport: { width: 800, height: 600 } });
	const errors = [], warnings = [];
	p.on('pageerror', (e) => errors.push(e.message));
	p.on('console', (m) => (m.type() === 'error' ? errors : m.type() === 'warning' ? warnings : []).push(m.text()));
	// (the islands' nodes, before the loader runs: readystatechange to interactive comes before deferred scripts)
	await p.addInitScript(() => {
		document.addEventListener('readystatechange', () => {
			if (document.readyState !== 'interactive') return;
			window.before = {};
			for (const el of document.querySelectorAll('hxmc-island[data-island]')) {
				const all = [];
				const walk = (n) => { for (const c of n.childNodes) { if (c.nodeType !== 8 || c.data !== '[') all.push(c); walk(c); } };
				walk(el);
				window.before[el.dataset.island] = all;
			}
		});
	});
	await p.goto(url);
	const hydrated = (name) => p.waitForSelector(`hxmc-island[data-island="${name}"][data-hydrated]`, { state: 'attached', timeout: 15000 });
	await hydrated('counter');
	await hydrated('small');
	const kept = await p.evaluate(() => Object.fromEntries(['counter', 'small'].map((name) => {
		const el = document.querySelector(`hxmc-island[data-island="${name}"]`), now = [];
		const walk = (n) => { for (const c of n.childNodes) { now.push(c); walk(c); } };
		walk(el);
		const before = window.before[name];
		return [name, before.length > 0 && before.length === now.length && before.every((n, i) => n === now[i] && n.isConnected) ? 'kept' : el.innerHTML];
	})));
	check('hydration keeps every node (counter: shared bundle)', kept.counter === 'kept', kept.counter);
	check('hydration keeps every node (small: its own bundle)', kept.small === 'kept', kept.small);
	// reactive afterwards
	await p.click('.inc');
	await p.fill('.name', 'Ann');
	await p.click('.small');
	await p.click('.small');
	const state = await p.evaluate(() => {
		const s = document.querySelector('.counter');
		return {
			count: s.querySelector('.count').textContent, data: s.dataset.count, color: s.style.color, hello: s.querySelector('.hello').textContent,
			items: [...s.querySelectorAll('li')].map((l) => l.textContent).join(','), touched: !!s.querySelector('.touched') && !s.querySelector('.untouched'),
			r: s.querySelector('circle').getAttribute('r'), small: document.querySelector('.small').textContent,
		};
	});
	check('reactive after hydration', JSON.stringify(state) === JSON.stringify({
		count: '4', data: '4', color: 'green', hello: 'Hello, Ann!', items: 'one,two,item 4', touched: true, r: '8', small: 'Clicked 2 times',
	}), state);
	// the mismatch
	await hydrated('mismatch');
	const mismatch = await p.evaluate(() => document.querySelector('.mismatch').innerHTML);
	check('a mismatch is rendered again', mismatch === '<b>client</b>', mismatch);
	check('with a warning (debug build)', warnings.some((w) => w.startsWith('helder.web: hydration mismatch: <b> expected, <i> found')), warnings);
	// JavaScript calling WebAssembly
	await p.waitForFunction(() => !document.querySelector('.lab').textContent.startsWith('loading'), null, { timeout: 15000 }).catch(() => {});
	const lab = await p.evaluate(() => document.querySelector('.lab').textContent);
	check('a JavaScript island calls lab.wasm', lab === 'sum 5; invert ok 65536; greet Hello, page, from WebAssembly; half 2.5; even true false', lab);
	// the WebAssembly island: fetched once in view
	await p.waitForTimeout(500);
	check('the cube is not fetched before it is in view', !requested.includes('/cube.wasm') && !requested.includes('/gfx/imports.mjs'),
		requested.filter((r) => r.endsWith('.wasm')));
	await p.locator('#cube').scrollIntoViewIfNeeded();
	await p.waitForSelector('#cube[data-hydrated]', { state: 'attached', timeout: 30000 }).catch(() => {});
	const cube = await p.evaluate(async () => {
		const r = await window.hxmcWasm.cube;
		return { backend: r.host.gfx.backend, exit: r.host.exitCode };
	}).catch((e) => ({ error: e.message }));
	check('the cube runs once in view', requested.includes('/cube.wasm') && ['webgpu', 'webgl2'].includes(cube.backend) && cube.exit === null, cube);
	// ui's <Surface> in the page: its program on the page's canvas, the canvas's size the page's styles, followed
	await p.locator('#counter-ui').scrollIntoViewIfNeeded();
	await p.waitForSelector('#counter-ui[data-hydrated]', { state: 'attached', timeout: 30000 }).catch(() => {});
	const size = () => p.evaluate(() => {
		const c = document.querySelector('#counter-ui canvas');
		return { w: c.width, h: c.height, cw: Math.round(c.clientWidth * devicePixelRatio), ch: Math.round(c.clientHeight * devicePixelRatio) };
	});
	const surface = await p.evaluate(async () => {
		const r = await window.hxmcWasm['counter-ui'];
		return { backend: r.host.gfx.backend, exit: r.host.exitCode };
	}).catch((e) => ({ error: e.message }));
	await p.waitForTimeout(300);
	const s0 = await size();
	check('a ui <Surface> runs on the page', ['webgpu', 'webgl2'].includes(surface.backend) && surface.exit === null && s0.w === s0.cw && s0.h === s0.ch && s0.w > 0, { surface, s0 });
	await p.evaluate(() => (document.querySelector('#counter-ui').style.width = '400px'));
	await p.waitForTimeout(300);
	const s1 = await size();
	check('its canvas follows the page\'s styles', s1.w === Math.round(400 * (s1.cw / 400)) && s1.w === s1.cw && s1.w !== s0.w, { s0, s1 });
	check('no errors', errors.length === 0, errors);
	await p.close();
}
await browser.close();
server.close();

// sizes
for (const f of [path.join(dir, 'demo/counter.js'), path.join(dir, 'demo/islands.js'), pkg('web/loader.js')]) {
	const b = await readFile(f);
	console.log(`web.mjs: ${path.basename(f)}: ${b.length} bytes, ${gzipSync(b, { level: 9 }).length} gzipped`);
}
console.log(failed === 0 ? 'web.mjs: ok' : `web.mjs: ${failed} FAILED`);
process.exit(failed === 0 ? 0 : 1);
