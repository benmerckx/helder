// @hxmc/web in headless Chromium (make web-check): the DOM renderer's checks
// (DomTest.hx, domtest.js), then the demo page (packages/web/examples:
// DemoPage's index.html, DemoBundle's islands.js, Counter's counter.js,
// lab.wasm, cube.wasm) served as a static site with packages/web/loader.js
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
// then prints the sizes of counter.js (a small island alone) and loader.js.
//   node packages/web/test/web.mjs <dir: domtest.js, demo/>
// (Playwright from npm, with Chromium: npx playwright install chromium)
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
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
const pkg = (p) => path.join(here, '../..', p);
const files = {
	'/loader.js': pkg('web/loader.js'),
	'/web/imports.mjs': pkg('web/imports.mjs'),
	'/os/browser.mjs': pkg('os/browser.mjs'),
	'/os/imports.mjs': pkg('os/imports.mjs'),
	'/gfx/imports.mjs': pkg('gfx/imports.mjs'),
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
	check('with a warning (debug build)', warnings.some((w) => w.startsWith('hxmc.web: hydration mismatch: <b> expected, <i> found')), warnings);
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
