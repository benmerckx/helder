// The site in real browsers (Playwright: chromium, firefox, webkit), after
// `make site` (make site-check):
// - links: every page's links, scripts, stylesheets and islands' files point
//   at files of the site (or outside it), and every #anchor at an element of
//   its page (node alone, once);
// - pages: every page in Chromium (the key pages in Firefox and WebKit),
//   at a desktop's width and at a phone's (390 px): no script error, no
//   console error, no horizontal scrolling, every island it starts
//   hydrated (JavaScript islands) or running (WebAssembly ones); the menu
//   (a phone's) and the theme switch work;
// - the examples: each canvas example running with a graphics API once
//   its Run button is clicked, with no uncaught exception: at a phone's
//   width (WebGPU), a desktop's (WebGL2) and on an emulated Android phone
//   (touch, its user agent, WebGL2), those scrolled away stopped
//   (data-stop); the
//   triangle and the cube (still: ?angle through hxmcWasmOptions) read back
//   at 256x192 against packages/gfx/test/triangle.png and cube.png
//   (compare.mjs): WebGPU on SwiftShader and WebGL2 in Chromium, WebGL2 in
//   WebKit and, with an X display (xvfb-run, as on CI), in a headed Firefox
//   on Mesa's llvmpipe (headless Firefox has no WebGL: there the gfx
//   islands must fail and say so); the source tabs; web's Counter island
//   counting; the Lab island calling lab.wasm; the tone started by a click;
//   the cube on an emulated phone: a horizontal touch drag turns it, a
//   vertical swipe over it scrolls the page; the home page's spinning cube
//   held still while a finger or the mouse holds it (the mouse dragged off
//   the canvas), spinning again once let go;
// - the playground's compiler: its worker (site/client/Worker.hx) runs a
//   program with --interp, compiles it to HXB, answers diagnostics and a
//   completion, with each module (hih.wasm: exnref; hih-legacy.wasm: the
//   legacy instructions), and in Chromium runs a request again after a
//   fault of the engine (fault-worker.js); the playground page (Monaco blocked: its plain
//   editor) picks its module (?eh=legacy, and a Chromium without exnref)
//   and runs its first example;
// - with a benchmark history in the site (bench/): the compiler page's
//   Programs tables, and with ?bench-history one chart per case with a
//   hover tooltip, light and dark, and at a phone's width.
// Screenshots into $SCREENSHOTS when set.
//   node site/tools/browser-test.mjs bin/site [chromium firefox webkit]
import { createServer } from 'node:http';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const dir = process.argv[2];
const names = process.argv.length > 3 ? process.argv.slice(3) : ['chromium', 'firefox', 'webkit'];
const types = { '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html', '.css': 'text/css',
	'.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml', '.ttf': 'font/ttf' };
const modules = ['hih.wasm', 'hih-legacy.wasm'].filter((m) => existsSync(path.join(dir, m)));
// (/gfx-test/: packages/gfx/test, the golden images and their comparison)
const toolsDir = path.dirname(fileURLToPath(import.meta.url));
const gfxDir = path.join(toolsDir, '../../packages/gfx/test');
const server = createServer(async (req, res) => {
	let u = decodeURIComponent(new URL(req.url, 'http://x').pathname);
	if (u.endsWith('/') && u !== '/') u += 'index.html';
	const p = u.startsWith('/gfx-test/') ? path.join(gfxDir, u.slice(10)) : u === '/fault-worker.js' ? path.join(toolsDir, 'fault-worker.js') : path.join(dir, u);
	try {
		const b = u === '/' ? Buffer.from('<!doctype html><title>test</title>') : await readFile(p);
		res.writeHead(200, { 'content-type': u === '/' ? 'text/html' : types[path.extname(p)] || 'application/octet-stream' });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
}).listen(0);
const port = server.address().port;
const url = (p) => `http://localhost:${port}/${p}`;
const shots = process.env.SCREENSHOTS;
let failed = 0;
const check = (ok, what) => {
	console.log(`  ${ok ? 'ok' : 'FAILED'}: ${what}`);
	if (!ok) failed++;
	return ok;
};

// --- links ---

function htmlPages(rel = '') {
	const out = [];
	for (const n of readdirSync(path.join(dir, rel)).sort()) {
		const r = rel ? `${rel}/${n}` : n;
		if (statSync(path.join(dir, r)).isDirectory()) out.push(...htmlPages(r));
		else if (n.endsWith('.html')) out.push(r);
	}
	return out;
}
const PAGES = htmlPages();

function linkCheck() {
	const ids = new Map();
	const idsOf = (page) => {
		if (!ids.has(page)) ids.set(page, new Set([...readFileSync(path.join(dir, page), 'utf8').matchAll(/\sid="([^"]*)"/g)].map((m) => m[1])));
		return ids.get(page);
	};
	// (files the site's build adds only with LIX_DIR or BENCH_DATA)
	const optional = (f) => f.startsWith('tools/lix-') || f.startsWith('bench/');
	const broken = [];
	let n = 0;
	for (const page of PAGES) {
		const html = readFileSync(path.join(dir, page), 'utf8');
		const refs = [];
		for (const m of html.matchAll(/\s(?:href|src|data-src|data-wasm|data-runner)="([^"]*)"/g)) refs.push(m[1]);
		for (const m of html.matchAll(/\sdata-(?:imports|fonts)="([^"]*)"/g)) refs.push(...JSON.parse(m[1].replace(/&quot;/g, '"')));
		for (let ref of refs) {
			ref = ref.replace(/&amp;/g, '&');
			if (/^(https?:|mailto:|data:)/.test(ref)) continue;
			n++;
			const [p, hash] = ref.split('#');
			const file = p === '' ? page : path.posix.normalize(path.posix.join(path.posix.dirname(page), p.split('?')[0])).replace(/\/$/, '/index.html');
			if (optional(file)) continue;
			if (!existsSync(path.join(dir, file)) || statSync(path.join(dir, file)).isDirectory()) broken.push(`${page}: ${ref} (no ${file})`);
			else if (hash && file.endsWith('.html') && !idsOf(file).has(decodeURIComponent(hash))) broken.push(`${page}: ${ref} (no #${hash})`);
		}
		// (and each id once)
		const seen = new Set();
		for (const m of html.matchAll(/\sid="([^"]*)"/g)) {
			if (seen.has(m[1])) broken.push(`${page}: id ${m[1]} twice`);
			seen.add(m[1]);
		}
	}
	for (const b of broken.slice(0, 40)) console.log('    ' + b);
	check(broken.length === 0, `links: ${n} links of ${PAGES.length} pages, ${broken.length} broken`);
}

// --- pages ---

const optionalUrl = (u) => /\/bench\/[^/]*\.json/.test(new URL(u).pathname);

// the pages every browser checks; Chromium checks them all
const KEY = ['index.html', 'examples.html', 'docs/index.html', 'docs/using.html', 'docs/api/ui.html', 'compiler.html', 'playground.html', 'story.html'];

// an uncaught error's stack as the page sees it, WebAssembly frames included
// (a pageerror's stack has only the JavaScript ones), as a console error
const stacks = () => addEventListener('error', (e) => e.error?.stack && console.error('stack: ' + e.error.stack.split('\n').slice(0, 24).join(' < ')));

// a page scrolled through (so that its islands start), then every island it
// started hydrated or failed; {errors, islands, failedIslands, scroll}
async function visit(page, p, { gfxErrors = false } = {}) {
	const errors = [];
	page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
	page.on('crash', () => errors.push('the page crashed'));
	await page.addInitScript(stacks);
	// (a missing file by its address, not the console's message; the editor
	// from the CDN is blocked, the benchmark history optional)
	page.on('console', (m) => m.type() === 'error' && !m.text().startsWith('Failed to load resource') && errors.push(m.text()));
	page.on('response', (r) => r.status() >= 400 && !optionalUrl(r.url()) && errors.push(`${r.status()} ${r.url()}`));
	page.on('requestfailed', (r) => !/cdn\.jsdelivr\.net/.test(r.url()) && !optionalUrl(r.url()) && errors.push(`failed ${r.url()}`));
	await page.route(/^https:\/\/cdn\.jsdelivr\.net\//, (r) => r.abort());
	await page.goto(url(p));
	const h = await page.evaluate(() => document.documentElement.scrollHeight);
	for (let y = 0; y < h; y += 500) {
		await page.evaluate((y) => scrollTo(0, y), y);
		await page.waitForTimeout(60);
	}
	// (an island scrolled past between two frames is never seen: each one not
	// started yet brought into view, in turn)
	for (let k = 0; k < 80; k++) {
		const next = await page.evaluate(() => {
			const started = (el) => ['data-hydrated', 'data-error', 'data-loading', 'data-stopped'].some((a) => el.hasAttribute(a));
			const el = [...document.querySelectorAll('hxmc-island[data-load="visible"]')].find((el) => !started(el) && (el.testSeen || 0) < 3);
			if (!el) return false;
			el.testSeen = (el.testSeen || 0) + 1;
			for (const o of document.querySelectorAll('[data-test-current]')) o.removeAttribute('data-test-current');
			el.setAttribute('data-test-current', '');
			el.scrollIntoView({ block: 'center' });
			return true;
		});
		// (until the loader starts it: a busy page sees it late; else tried again)
		if (next) await page.waitForFunction(() => { const el = document.querySelector('[data-test-current]'); return !el || ['data-hydrated', 'data-error', 'data-loading'].some((a) => el.hasAttribute(a)); }, null, { timeout: 3000 }).catch(() => {});
		if (!next) break;
		await page.waitForTimeout(150);
	}
	await page.evaluate(() => scrollTo(0, 0));
	// (back at the top, those in view there start again: data-stop)
	await page.evaluate(() => new Promise((ok) => requestAnimationFrame(() => requestAnimationFrame(ok))));
	// (every island but those a click starts: hydrated, or failed, or stopped
	// once scrolled away; none still starting)
	await page.waitForFunction(() => [...document.querySelectorAll('hxmc-island')].every((el) => el.dataset.load === 'click'
		|| (!el.hasAttribute('data-loading') && (el.hasAttribute('data-stopped') || el.hasAttribute('data-hydrated') || el.hasAttribute('data-error')))), null, { timeout: 90000 }).catch(() => {});
	return page.evaluate(() => {
		const all = [...document.querySelectorAll('hxmc-island')];
		return {
			islands: all.length,
			pending: all.filter((el) => el.dataset.load !== 'click' && !el.hasAttribute('data-stopped') && !el.hasAttribute('data-hydrated') && !el.hasAttribute('data-error')).map((el) => el.id || el.dataset.island),
			failedIslands: all.filter((el) => el.hasAttribute('data-error')).map((el) => `${el.id || el.dataset.island}: ${el.dataset.error}`),
			gfxIslands: all.filter((el) => (el.dataset.imports || '').includes('gfx/')).map((el) => el.id),
			scroll: document.documentElement.scrollWidth - document.documentElement.clientWidth,
		};
	}).then((r) => ({ ...r, errors }));
}

async function pagesTest(browser, name, hasGfx) {
	const pages = name === 'chromium' ? PAGES : KEY;
	for (const width of [1280, 390]) {
		const context = await browser.newContext({ viewport: { width, height: width < 600 ? 844 : 900 }, ...(width < 600 && name !== 'firefox' ? { isMobile: true, hasTouch: true } : {}) });
		let bad = [];
		for (const p of pages) {
			const page = await context.newPage();
			let r;
			try {
				r = await visit(page, p);
			} catch (e) {
				r = { errors: [e.message.split('\n')[0]], pending: [], failedIslands: [], gfxIslands: [], scroll: 0 };
			}
			// (without WebGL, a browser's gfx islands fail, and say so)
			const gfxFail = (s) => !hasGfx && r.gfxIslands.some((id) => s.startsWith(id + ':') || s.includes('hxmc: island'));
			const failedIslands = r.failedIslands.filter((s) => !gfxFail(s));
			const errors = r.errors.filter((e) => !(!hasGfx && /island|WebGL|WebGPU|gfx/i.test(e)));
			const ok = errors.length === 0 && failedIslands.length === 0 && r.pending.length === 0 && r.scroll <= 0;
			if (!ok) bad.push(`${p}: ${JSON.stringify({ errors, failedIslands, pending: r.pending, scroll: r.scroll })}`);
			if (shots && KEY.includes(p)) await page.screenshot({ path: path.join(shots, `page-${name}-${width}-${p.replace(/\//g, '_')}.png`), fullPage: true });
			await page.close();
		}
		for (const b of bad) console.log('    ' + b.slice(0, 2000));
		check(bad.length === 0, `pages at ${width} px: ${pages.length - bad.length} of ${pages.length} rendered, islands hydrated, no errors, no horizontal scrolling`);
		await context.close();
	}
}

// the menu (a phone's), the theme switch, the source tabs, web's Counter
// island, the Lab island, the tone
async function interactTest(browser, name) {
	const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
	const page = await context.newPage();
	await page.goto(url('index.html'));
	await page.waitForSelector('hxmc-island[data-island="menu"][data-hydrated]', { timeout: 30000 });
	const hiddenBefore = await page.isHidden('#nav-links');
	await page.click('.menu');
	check(hiddenBefore && (await page.isVisible('#nav-links a[href="examples.html"]')), 'the menu opens on a phone');
	await page.waitForSelector('hxmc-island[data-island="theme"][data-hydrated]', { timeout: 30000 });
	const bg = () => page.evaluate(() => getComputedStyle(document.body).backgroundColor);
	const before = await bg();
	await page.click('.theme');
	const theme = await page.evaluate(() => document.documentElement.dataset.theme);
	const after = await bg();
	await page.reload();
	const kept = await page.evaluate(() => document.documentElement.dataset.theme);
	check(before !== after && theme === kept && !!theme, `the theme switch: ${theme}, kept after a reload (${before} -> ${after})`);
	await page.evaluate(() => localStorage.clear());
	await context.close();

	const ex = await browser.newPage({ viewport: { width: 1280, height: 900 } });
	await ex.route(/^https:\/\/cdn\.jsdelivr\.net\//, (r) => r.abort());
	await ex.goto(url('examples.html'));
	// the cube's source tabs
	await ex.locator('#gfx-cube .tabs').scrollIntoViewIfNeeded();
	await ex.waitForSelector('#gfx-cube hxmc-island[data-island="tabs"][data-hydrated]', { timeout: 30000 });
	await ex.click('#gfx-cube .tabs button:nth-child(2)');
	const tabs = await ex.evaluate(() => [document.getElementById('src-gfx-cube-0').hidden, document.getElementById('src-gfx-cube-1').hidden]);
	check(tabs[0] === true && tabs[1] === false, `the source tabs switch files (${tabs})`);
	// web's Counter island
	const counter = ex.locator('#web-counter hxmc-island[data-island="small"]');
	await counter.scrollIntoViewIfNeeded();
	await ex.waitForSelector('#web-counter hxmc-island[data-island="small"][data-hydrated]', { timeout: 30000 });
	await ex.click('#web-counter button.small');
	await ex.click('#web-counter button.small');
	const counted = await ex.textContent('#web-counter button.small');
	check(counted === 'Clicked 2 times', `the Counter island counts: ${counted}`);
	// the Lab island
	await ex.locator('#web-lab .lab').scrollIntoViewIfNeeded();
	let lab = '';
	try {
		await ex.waitForFunction(() => /Hello, page, from WebAssembly/.test(document.querySelector('#web-lab .lab-greet')?.textContent ?? ''), null, { timeout: 30000 });
		await ex.fill('#web-lab .lab-a', '40');
		await ex.click('#web-lab .lab-invert');
		await ex.waitForFunction(() => /inverted correctly/.test(document.querySelector('#web-lab .lab-inverted').textContent), null, { timeout: 10000 });
		lab = await ex.evaluate(() => [document.querySelector('#web-lab .lab-greet').textContent, document.querySelector('#web-lab .lab-sum').textContent, document.querySelector('#web-lab .lab-inverted').textContent].join(' | '));
	} catch (e) {
		lab = e.message.split('\n')[0];
	}
	check(/from WebAssembly.*\| 43 \| 1 MB inverted correctly/.test(lab), `the Lab island calls lab.wasm: ${lab}`);
	// the tone, started by a click
	if (existsSync(path.join(dir, 'examples/os-tone.wasm'))) {
		const errors = [];
		ex.on('pageerror', (e) => errors.push(e.message));
		await ex.locator('#os-tone .play-sound').scrollIntoViewIfNeeded();
		const idle = await ex.evaluate(() => !document.querySelector('#os-tone hxmc-island').hasAttribute('data-hydrated'));
		await ex.click('#os-tone .play-sound');
		const r = await ex.waitForFunction(() => { const el = document.querySelector('#os-tone hxmc-island'); return el.hasAttribute('data-hydrated') || el.dataset.error; }, null, { timeout: 30000 }).then(() => ex.evaluate(() => document.querySelector('#os-tone hxmc-island').dataset.error ?? 'started')).catch((e) => e.message.split('\n')[0]);
		check(idle && r === 'started' && errors.length === 0, `the tone: fetched only on a click, then ${r}${errors.length ? '; ' + errors.join('; ') : ''}`);
	}
	await ex.close();
}

// a gfx example's island read back at the golden image's size (the
// examples page; still, through hxmcWasmOptions), through the API expected
// (webgpu, webgl2); expect null: it must fail and say so
async function gfxTest(browser, label, id, golden, expect, gfx) {
	const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
	const errors = [];
	page.on('pageerror', (e) => errors.push(e.message));
	page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
	await page.route(/^https:\/\/cdn\.jsdelivr\.net\//, (r) => r.abort());
	await page.addInitScript(([id, gfx]) => {
		// (single-sampled, as natively: the golden images)
		window.hxmcWasmOptions = { ['demo-' + id]: { args: id === 'gfx-cube' ? ['--angle', '0.6'] : [], antialias: false, ...(gfx ? { gfx } : {}) } };
	}, [id, gfx]);
	await page.goto(url('examples.html'));
	await page.evaluate((id) => document.getElementById(id).scrollIntoView(), id);
	await run(page, id);
	let r;
	try {
		await page.waitForFunction((id) => { const el = document.getElementById('demo-' + id); return el.hasAttribute('data-hydrated') || el.hasAttribute('data-error'); }, id, { timeout: 60000 });
		r = await page.evaluate(async ([id, golden]) => {
			const el = document.getElementById('demo-' + id);
			if (el.dataset.error) return { drawn: false, text: el.dataset.error };
			const { host } = await hxmcWasm['demo-' + id];
			const c = el.querySelector('canvas');
			c.style.boxSizing = 'content-box';
			c.style.width = '256px';
			c.style.height = '192px';
			await new Promise((ok) => requestAnimationFrame(() => requestAnimationFrame(ok)));
			await new Promise((ok) => requestAnimationFrame(() => requestAnimationFrame(ok)));
			const [{ decode, compare }, px] = await Promise.all([import('/gfx-test/compare.mjs'), host.gfx.readPixels()]);
			return { drawn: true, backend: host.gfx.backend, badge: el.dataset.gfx, ...compare(id, px, await decode('/gfx-test/' + golden)) };
		}, [id, golden]);
	} catch (e) {
		r = { drawn: false, text: e.message.split('\n')[0] };
	}
	if (shots) await page.locator('#' + id).screenshot({ path: path.join(shots, `${id}-${label}-${expect ?? 'none'}.png`) });
	await page.close();
	const ok = !expect ? !r.drawn && /WebGPU|WebGL/.test(r.text) : errors.length === 0 && r.drawn && r.ok && r.backend === expect && r.badge === expect;
	return check(ok, `${id} (${label}) ${r.backend ? 'through ' + r.backend + ', ' : ''}${r.text}${errors.length ? '; errors: ' + errors.join('; ') : ''}`);
}

// a gallery demo (example id) run: its Run button clicked unless it has
// started already (on a large screen it starts once in view)
async function run(page, id) {
	await page.evaluate((id) => {
		const el = document.getElementById('demo-' + id);
		if (el && el.dataset.load === 'click' && !el.hasAttribute('data-hydrated') && !el.hasAttribute('data-loading')) el.querySelector('.run').click();
	}, id);
}

// every canvas example running, with a graphics API, when run in turn (a
// phone's width: a tap starts each), no exception in the second after it
// starts; those scrolled away stopped, their GPU memory given back. As
// label: a phone's width; a desktop's, through WebGL2; an emulated Android
// phone (touch, its user agent), through WebGL2
const ANDROID = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36';
async function examplesTest(browser, label = 'phone') {
	const options = label === 'desktop' ? { viewport: { width: 1280, height: 900 } } : label === 'android'
		? { viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2.625, userAgent: ANDROID } : { viewport: { width: 390, height: 844 } };
	const page = await browser.newPage(options);
	if (label !== 'phone') await page.addInitScript(() => {
		window.hxmcWasmOptions = new Proxy({}, { get: () => ({ gfx: 'webgl2' }) });
	});
	const r = await visit(page, 'examples.html');
	const ids = await page.evaluate(() => [...document.querySelectorAll('.example-demo hxmc-island[data-wasm]')].filter((el) => el.querySelector('canvas')).map((el) => el.id.slice(5)));
	const facts = [];
	for (const id of ids) {
		await page.evaluate((id) => document.getElementById('demo-' + id).scrollIntoView({ block: 'center' }), id);
		await run(page, id);
		await page.waitForFunction((id) => { const el = document.getElementById('demo-' + id); return el.hasAttribute('data-hydrated') || el.hasAttribute('data-error'); }, id, { timeout: 60000 }).catch(() => {});
		await page.waitForTimeout(1000);
		facts.push(await page.evaluate((id) => { const el = document.getElementById('demo-' + id); return { id: el.id, gfx: el.dataset.gfx ?? null, error: el.dataset.error ?? null }; }, id));
	}
	const stopped = await page.evaluate(() => document.querySelectorAll('hxmc-island[data-stopped]').length);
	await page.close();
	const bad = facts.filter((f) => !f.gfx || f.error);
	check(facts.length > 0 && bad.length === 0 && r.errors.length === 0 && stopped >= facts.length - 3, `examples (${label}): ${facts.length} canvas examples running (${facts.map((f) => f.id + ' ' + f.gfx).join(', ')}), ${stopped} stopped once scrolled away${bad.length ? '; not: ' + JSON.stringify(bad) : ''}${r.errors.length ? '; errors: ' + r.errors.join('; ') : ''}`);
}

// the cube on a phone (touch emulated, a 390x844 viewport): a horizontal
// touch drag on its canvas turns it (the frame read back before and after
// differs, the page does not scroll), and a vertical swipe that starts on
// it scrolls the page (the canvas's touch-action is pan-y: loader.js). The
// touches are Chromium's own input (DevTools' Input.dispatchTouchEvent), so
// that the browser decides what it pans as on a phone.
async function touchTest(browser) {
	const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
	const page = await context.newPage();
	const errors = [];
	page.on('pageerror', (e) => errors.push(e.message));
	await page.addInitScript(() => (window.hxmcWasmOptions = { 'demo-gfx-cube': { args: ['--angle', '0.6'] } }));
	let r = {}, ok = false;
	try {
		await page.goto(url('examples.html'));
		await page.evaluate(() => document.querySelector('#demo-gfx-cube canvas').scrollIntoView({ block: 'center' }));
		await page.tap('#demo-gfx-cube .run');
		await page.waitForSelector('#demo-gfx-cube[data-hydrated]', { timeout: 60000 });
		const cdp = await context.newCDPSession(page);
		const frames = (n) => page.evaluate((n) => new Promise((ok) => { const f = () => (n-- > 0 ? requestAnimationFrame(f) : ok()); f(); }), n);
		const touch = async (from, to, steps = 12) => {
			await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: from[0], y: from[1] }] });
			for (let i = 1; i <= steps; i++) {
				const x = from[0] + (to[0] - from[0]) * i / steps, y = from[1] + (to[1] - from[1]) * i / steps;
				await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y }] });
				await page.waitForTimeout(16);
			}
			await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
		};
		const state = () => page.evaluate(async () => {
			const { host } = await hxmcWasm['demo-gfx-cube'];
			const c = document.querySelector('#demo-gfx-cube canvas'), px = await host.gfx.readPixels(), b = c.getBoundingClientRect();
			return { scrollY: Math.round(scrollY), box: [b.left, b.top, b.width, b.height], width: px.width, height: px.height, data: Array.from(px.data) };
		});
		await frames(2);
		const before = await state();
		const [x, y, w, h] = before.box;
		await touch([x + w * 0.25, y + h / 2], [x + w * 0.75, y + h / 2 + 4]);
		await page.waitForTimeout(500);
		await frames(2);
		const turned = await state();
		let differ = 0;
		for (let p = 0; p < before.data.length; p += 4)
			if (Math.max(...[0, 1, 2].map((k) => Math.abs(before.data[p + k] - turned.data[p + k]))) > 8) differ++;
		r.turned = `${differ} of ${before.width * before.height} pixels changed`;
		r.dragScroll = turned.scrollY - before.scrollY;
		await touch([x + w / 2, y + h / 2], [x + w / 2 + 4, y + h / 2 - 300]);
		await page.waitForTimeout(500);
		const swiped = await state();
		r.swipeScroll = swiped.scrollY - turned.scrollY;
		ok = differ > 0.02 * before.width * before.height && Math.abs(r.dragScroll) <= 1 && r.swipeScroll > 100 && errors.length === 0;
	} catch (e) {
		r.error = e.message.split('\n')[0];
	}
	await context.close();
	check(ok, `the cube on a phone: ${JSON.stringify(r)}${errors.length ? '; errors: ' + errors.join('; ') : ''}`);
}

// the home page's cube, spinning on its own, held: once a drag has turned
// it, it stays still while the finger (an emulated phone's touch, as
// touchTest) or the mouse's button is down, and the mouse's drag may leave
// the canvas (captured: the release outside it still lets go); once let go
// it spins again. Frames read back: the same while held, not after.
async function holdTest(browser) {
	const results = {};
	for (const kind of ['touch', 'mouse']) {
		const context = await browser.newContext(kind === 'touch' ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true } : { viewport: { width: 1280, height: 900 } });
		const page = await context.newPage();
		const errors = [];
		page.on('pageerror', (e) => errors.push(e.message));
		const r = (results[kind] = {});
		try {
			await page.goto(url('index.html'));
			await page.evaluate(() => document.querySelector('#demo-gfx-cube canvas').scrollIntoView({ block: 'center' }));
			await page.waitForSelector('#demo-gfx-cube[data-hydrated]', { timeout: 60000 });
			const frames = (n) => page.evaluate((n) => new Promise((ok) => { const f = () => (n-- > 0 ? requestAnimationFrame(f) : ok()); f(); }), n);
			const pixels = () => page.evaluate(async () => Array.from((await (await hxmcWasm['demo-gfx-cube']).host.gfx.readPixels()).data));
			const differ = (a, b) => { let n = 0; for (let p = 0; p < a.length; p += 4) if (Math.max(Math.abs(a[p] - b[p]), Math.abs(a[p + 1] - b[p + 1]), Math.abs(a[p + 2] - b[p + 2])) > 8) n++; return n; };
			const wait = async (ms) => { await page.waitForTimeout(ms); await frames(2); };
			const b = await page.evaluate(() => { const r = document.querySelector('#demo-gfx-cube canvas').getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; });
			const [x, y, w, h] = b, cy = y + h / 2;
			const spinning = await pixels();
			await wait(400);
			r.spins = differ(spinning, await pixels());
			let up;
			if (kind === 'touch') {
				const cdp = await context.newCDPSession(page);
				const at = (px) => [{ x: px, y: cy }];
				await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: at(x + w * 0.3) });
				for (let i = 1; i <= 8; i++) {
					await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: at(x + w * (0.3 + 0.04 * i)) });
					await page.waitForTimeout(16);
				}
				up = () => cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
			} else {
				await page.mouse.move(x + w * 0.5, cy);
				await page.mouse.down();
				await page.mouse.move(x + w * 0.7, cy, { steps: 6 });
				// (off the canvas, to its left: the drag goes on)
				await page.mouse.move(x - 40, cy + h * 0.3, { steps: 6 });
				up = () => page.mouse.up();
			}
			// (resting: no glide, no spin)
			await wait(300);
			const held = await pixels();
			await wait(600);
			r.held = differ(held, await pixels());
			await up();
			await wait(1200);
			r.released = differ(held, await pixels());
			const area = w * h * 0.002;
			r.ok = r.spins > area && r.held === 0 && r.released > area && errors.length === 0;
		} catch (e) {
			r.error = e.message.split('\n')[0];
		}
		if (errors.length) r.errors = errors;
		await context.close();
	}
	check(results.touch.ok && results.mouse.ok, `the home page's cube held still while dragged (touch, mouse off the canvas), spinning again once let go: ${JSON.stringify(results)}`);
}

// --- the playground ---

const code = 'class Main {\n\tstatic function main() {\n\t\tvar a = [for (i in 0...5) i * i];\n\t\ttrace("Hello " + a);\n\t\ttry throw "oops" catch (e:String) Sys.println("caught " + e);\n\t\tSys.println(haxe.Json.stringify({ok: true}));\n\t}\n}\n';

async function inPage([code, wasm]) {
	const w = new Worker('worker.js');
	const replies = [];
	let wake = null;
	w.onmessage = (e) => { replies.push(e.data); if (wake) wake(); };
	w.onerror = (e) => { replies.push({ type: 'failed', message: e.message }); if (wake) wake(); };
	async function until(pred) {
		while (true) {
			const i = replies.findIndex(pred);
			if (i >= 0) return replies.splice(i, 1)[0];
			await new Promise((r) => (wake = r));
		}
	}
	const log = [];
	const t0 = performance.now();
	w.postMessage({ type: 'module', module: await WebAssembly.compileStreaming(fetch(wasm)) });
	w.postMessage({ type: 'warmup' });
	const ready = await until((r) => r.type === 'ready' || r.type === 'failed');
	log.push(`ready ${ready.type} ${ready.message ?? ''} ${Math.round(performance.now() - t0)} ms`);
	if (ready.type === 'failed') return log;
	// (three times: the engines optimize the module's code while it runs)
	for (let k = 0; k < 3; k++) {
		w.postMessage({ type: 'compile', id: 1, mode: 'run', main: 'Main', file: 'Main.hx', code });
		const done = await until((r) => r.type === 'done' || r.type === 'failed');
		for (const r of replies.splice(0)) if (k == 0) log.push(`${r.type} ${r.text}`);
		log.push(`run ${done.status} ${Math.round(done.ms)} ms ${done.message ?? ''}`);
	}
	w.postMessage({ type: 'compile', id: 2, mode: 'hxb', main: 'Main', file: 'Main.hx', code });
	const hxb = await until((r) => r.type === 'done' || r.type === 'failed');
	replies.splice(0);
	log.push(`hxb ${hxb.status} ${hxb.zip ? hxb.zip.byteLength + ' bytes' : hxb.message} ${Math.round(hxb.ms)} ms`);
	w.postMessage({ type: 'check', id: 3, main: 'Main', file: 'Main.hx', code: code.replace('trace(', 'trace(undefinedThing + ') });
	const check = await until((r) => r.type === 'check' || r.type === 'failed');
	log.push(`check ${check.status} ${JSON.stringify(check.output)}`);
	const at = code.indexOf(' + a') + 4;
	const dcode = code.slice(0, at) + '.' + code.slice(at);
	w.postMessage({ type: 'display', id: 4, main: 'Main', file: 'Main.hx', code: dcode,
		request: { jsonrpc: '2.0', id: 1, method: 'display/completion', params: { file: '/work/Main.hx', offset: at + 1, wasAutoTriggered: true } } });
	const disp = await until((r) => r.type === 'display' || r.type === 'failed');
	log.push(`display ${disp.status} ${(disp.output ?? disp.message).slice(0, 120)}`);
	w.terminate();
	return log;
}

// the worker after a fault of the engine (WebKit 26.0 at times faults in
// correct code; fault-worker.js fakes one): the request runs again in a
// fresh instance, and its reply is the second run's
async function faultTest(browser, wasm) {
	const page = await browser.newPage();
	await page.goto(url(''));
	const r = await page.evaluate(async ([code, wasm]) => {
		const w = new Worker('fault-worker.js');
		const replies = [];
		let wake = null;
		w.onmessage = (e) => { replies.push(e.data); if (wake) wake(); };
		const until = async (pred) => { for (;;) { const i = replies.findIndex(pred); if (i >= 0) return replies.splice(i, 1)[0]; await new Promise((r) => (wake = r)); } };
		w.postMessage({ type: 'module', module: await WebAssembly.compileStreaming(fetch(wasm)) });
		w.postMessage({ type: 'warmup' });
		await until((r) => r.type === 'ready' || r.type === 'failed');
		w.postMessage({ type: 'compile', id: 1, mode: 'run', main: 'Main', file: 'Main.hx', code });
		const done = await until((r) => r.type === 'done' || r.type === 'failed');
		w.terminate();
		return { type: done.type, status: done.status, message: done.message, out: replies.filter((r) => r.type === 'out').map((r) => r.text) };
	}, [code, wasm]).catch((e) => ({ message: e.message.split('\n')[0] }));
	await page.close();
	check(r.type === 'done' && r.status === 0 && r.out?.[0]?.startsWith('Main.hx:4: Hello'), `the worker after a fault of the engine (${wasm}): ${JSON.stringify(r).slice(0, 300)}`);
}

// the playground page: the module it fetches, then a Run of the example it loads
async function pageTest(browser, query, expect) {
	const page = await browser.newPage();
	const fetched = [];
	// (what the page and its workers said: on a failure, with where it stood)
	const said = [];
	page.on('request', (r) => { const p = new URL(r.url()).pathname; if (/^\/hih(-legacy)?\.wasm$/.test(p)) fetched.push(path.basename(p)); });
	page.on('pageerror', (e) => said.push('pageerror: ' + e.message));
	page.on('console', (m) => said.push(`console.${m.type()}: ${m.text()}`));
	page.on('crash', () => said.push('the page crashed'));
	page.on('worker', (w) => w.on('close', () => said.push('a worker closed')));
	await page.addInitScript(stacks);
	await page.route(/^https:\/\/cdn\.jsdelivr\.net\//, (r) => r.abort());
	let ready = '', run = '', stage = 'loading';
	try {
		await page.goto(url('playground.html' + query));
		await page.waitForFunction(() => /^Ready|cannot|could not/.test(document.getElementById('state').textContent), null, { timeout: 180000 });
		ready = await page.evaluate(() => document.getElementById('state').textContent);
		if (ready.startsWith('Ready')) {
			stage = 'the example';
			await page.waitForFunction(() => document.querySelector('textarea[aria-label="Haxe source"]')?.value, null, { timeout: 30000 });
			stage = 'running';
			await page.click('#run');
			// (its exit, or the compiler instance failing: Playground.hx prints that and starts a new one)
			await page.waitForFunction(() => /^exit/.test(document.getElementById('timing').textContent) || /The compiler instance failed/.test(document.getElementById('out').textContent), null, { timeout: 180000 });
			run = await page.evaluate(() => {
				const timing = document.getElementById('timing').textContent, out = document.getElementById('out').textContent.trim();
				return /^exit/.test(timing) ? timing + ': ' + out.split('\n')[0] : 'failed: ' + out.slice(0, 3000);
			});
			if (!run.startsWith('exit')) for (const l of said) console.log('    ' + l.slice(0, 2000));
		}
	} catch (e) {
		const at = await page.evaluate(() => ['state', 'timing', 'out'].map((id) => `${id}: ${JSON.stringify((document.getElementById(id)?.textContent ?? "").slice(0, 3000))}`).join(', ')).catch(() => 'the page is gone');
		run = `${e.message.split('\n')[0]} (${stage}; ${at})`;
		for (const l of said) console.log('    ' + l.slice(0, 2000));
	}
	await page.close().catch(() => {});
	return check(fetched.length === 1 && fetched[0] === expect && run.startsWith('exit 0'), `playground.html${query}: fetched ${fetched.join(', ') || 'nothing'} (expected ${expect}); ${ready}; ${run}`);
}

// the Programs benchmarks: the latest run's table and the compile-time table
// below it, with the "Over time" charts hidden; then with ?bench-history (the
// charts' code kept for later) one chart per case with a hover tooltip; at a
// phone's width, no horizontal scrolling of the page
async function benchTest(browser, name) {
	let ok = true;
	const latest = existsSync(path.join(dir, 'bench/latest.json'));
	const views = [
		{ colorScheme: 'light', width: 1100, query: '' },
		{ colorScheme: 'dark', width: 1100, query: '' },
		{ colorScheme: 'light', width: 1100, query: '?bench-history' },
		{ colorScheme: 'dark', width: 1100, query: '?bench-history' },
		{ colorScheme: 'light', width: 375, query: '' },
	];
	for (const { colorScheme, width, query } of views) {
		const view = `${colorScheme}, ${width} px${query ? ', ' + query : ''}`;
		let pass = true;
		const page = await browser.newPage({ colorScheme, viewport: { width, height: 900 } });
		const errors = [];
		page.on('pageerror', (e) => errors.push(e.message));
		await page.route(/^https:\/\/cdn\.jsdelivr\.net\//, (r) => r.abort());
		await page.goto(`http://localhost:${port}/compiler.html${query}`);
		await page.evaluate(() => document.getElementById('benchmarks').scrollIntoView());
		let facts = '';
		try {
			// (the tables: the latest run, which a history of imported points only lacks)
			if (latest) {
				await page.waitForSelector('#programs-results table', { timeout: 30000 });
				await page.waitForSelector('#programs-compile table', { timeout: 5000 });
			}
			if (query) {
				await page.waitForSelector('#programs-history svg', { timeout: 30000 });
				const svg = page.locator('#programs-history .plot svg').first();
				await svg.scrollIntoViewIfNeeded();
				const box = await svg.boundingBox();
				await svg.hover({ position: { x: box.width * 0.95, y: box.height / 2 } });
				await page.waitForSelector('#programs-history .tip:not([hidden])', { timeout: 5000 });
			} else {
				// (the history would have been fetched and drawn by now if it were shown)
				await page.waitForTimeout(500);
			}
			facts = await page.evaluate(() => {
				const q = (s) => document.querySelectorAll(s).length;
				const visible = (e) => !!e && e.getClientRects().length > 0 && getComputedStyle(e).visibility !== 'hidden';
				const compileCells = [...document.querySelectorAll('#programs-compile tbody tr:not(.ref) td.num')];
				return {
					rows: q('#programs-results tbody tr'),
					cols: q('#programs-results thead th'),
					tabs: [...document.querySelectorAll('#programs-results .tabs button')].map((b) => b.textContent).join(','),
					compileRows: q('#programs-compile tbody tr:not(.ref)'),
					compileCols: q('#programs-compile thead th'),
					compileVisible: visible(document.querySelector('#programs-compile table')),
					compileValues: compileCells.filter((td) => /\d/.test(td.textContent)).length,
					compileSplit: q('#programs-compile td .parts'),
					compileNote: (document.querySelector('#programs-compile .note')?.textContent ?? '').slice(0, 40),
					historyVisible: visible(document.getElementById('programs-over-time')),
					charts: q('#programs-history svg'),
					lines: q('#programs-history svg .series path'),
					tip: document.querySelector('#programs-history .tip')?.textContent.slice(0, 60) ?? '',
					series: getComputedStyle(document.documentElement).getPropertyValue('--s1').trim(),
					pageScroll: document.documentElement.scrollWidth - document.documentElement.clientWidth,
				};
			});
			if (latest && (facts.rows < 1 || !facts.compileVisible || facts.compileRows !== facts.rows || facts.compileCols !== facts.cols || facts.compileValues < 1 || !/Compile time/.test(await page.textContent('#programs-compile h4'))))
				pass = false;
			if (query ? !facts.historyVisible || facts.charts < 1 || facts.lines < 1 : facts.historyVisible || facts.charts > 0) pass = false;
			if (facts.pageScroll > 0) pass = false;
			if (process.env.SCREENSHOTS) {
				await page.locator('#benchmarks').screenshot({ path: path.join(process.env.SCREENSHOTS, `bench-${name}-${colorScheme}-${width}${query ? '-history' : ''}.png`) });
			}
		} catch (e) {
			pass = false;
			facts = e.message.split('\n')[0];
		}
		if (errors.length) pass = false;
		if (!pass) ok = false;
		console.log(`  benchmarks (${view}) ${pass ? 'ok' : 'FAILED'}: ${JSON.stringify(facts)}${errors.length ? '; errors: ' + errors.join('; ') : ''}`);
		await page.close();
	}
	return ok;
}

// --- the browsers ---

linkCheck();
// (Chromium: WebGPU on SwiftShader's Vulkan, as packages/gfx/test/web.mjs)
const WEBGPU = ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'];
const launches = names.map((name) => ({ name, label: name, opts: name === 'chromium' ? { args: WEBGPU } : {} }));
// (a Chromium without exnref: the playground falls back to the legacy module by itself)
if (names.includes('chromium') && modules.includes('hih-legacy.wasm'))
	launches.push({ name: 'chromium', label: 'chromium without exnref', opts: { args: ['--js-flags=--no-experimental-wasm-exnref'] }, noExnref: true });
const examples = existsSync(path.join(dir, 'examples/gfx-cube.wasm'));
for (const { name, label, opts, noExnref } of launches) {
	let browser;
	try {
		browser = await pw[name].launch(opts);
		console.log(`== ${label} ${browser.version()}`);
		if (noExnref) {
			const page = await browser.newPage();
			await page.goto(url(''));
			const err = await page.evaluate(async () => {
				try { await WebAssembly.compileStreaming(fetch('hih.wasm')); return 'compiled'; } catch (e) { return e.message; }
			});
			await page.close();
			check(err !== 'compiled', `hih.wasm does not compile: ${err}`);
			await pageTest(browser, '', 'hih-legacy.wasm');
			if (examples) await gfxTest(browser, 'chromium-no-exnref', 'gfx-cube', 'cube.png', 'webgl2');
			continue;
		}
		for (const wasm of modules) {
			const page = await browser.newPage();
			const said = [];
			page.on('crash', () => said.push('the page crashed'));
			page.on('console', (m) => said.push(`console.${m.type()}: ${m.text()}`));
			await page.goto(url(''));
			const log = await page.evaluate(inPage, [code, wasm]).catch((e) => [e.message.split('\n')[0], ...said]);
			await page.close().catch(() => {});
			console.log(`  ${wasm}`);
			for (const l of log) console.log('    ' + l);
			check(log.some((l) => l.startsWith('run 0')) && log.some((l) => l.startsWith('hxb 0')), `the worker with ${wasm}`);
		}
		if (name === 'chromium' && modules.length) await faultTest(browser, modules[0]);
		// (headless Firefox has no WebGL; with a display, a headed one has, on llvmpipe)
		const headed = name === 'firefox' && process.env.DISPLAY ? await pw.firefox.launch({ headless: false }) : null;
		const gfxBrowser = headed ?? browser;
		const hasGfx = name !== 'firefox' || !!headed;
		if (headed) console.log('  (the gfx examples in a headed Firefox on DISPLAY ' + process.env.DISPLAY + ')');
		await pagesTest(name === 'firefox' && headed ? headed : browser, name, hasGfx);
		if (examples) {
			await interactTest(browser, name);
			if (name === 'chromium') {
				for (const label of ['phone', 'desktop', 'android']) await examplesTest(browser, label);
				for (const [id, golden] of [['gfx-triangle', 'triangle.png'], ['gfx-cube', 'cube.png']]) {
					await gfxTest(browser, name, id, golden, 'webgpu');
					await gfxTest(browser, name, id, golden, 'webgl2', 'webgl2');
				}
				await touchTest(browser);
				await holdTest(browser);
			} else {
				for (const [id, golden] of [['gfx-triangle', 'triangle.png'], ['gfx-cube', 'cube.png']])
					await gfxTest(gfxBrowser, headed ? 'firefox-headed' : name, id, golden, hasGfx ? 'webgl2' : null);
			}
		}
		await headed?.close();
		if (existsSync(path.join(dir, 'bench/history.json')) && !(await benchTest(browser, name))) failed++;
		if (modules.length) {
			await pageTest(browser, '', 'hih.wasm');
			if (modules.includes('hih-legacy.wasm')) await pageTest(browser, '?eh=legacy', 'hih-legacy.wasm');
		}
	} catch (e) {
		check(false, `${label}: ${e.message.split('\n')[0]}`);
	} finally {
		if (browser) await browser.close();
	}
}
server.close();
console.log(failed ? `${failed} checks FAILED` : 'all checks passed');
process.exit(failed ? 1 : 0);
