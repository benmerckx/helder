// The DOM's widgets (packages/web, helder.web.widgets) under the theme's CSS
// (helder.theme.Css) in Chromium against shadcn/ui's own markup and CSS in
// Chromium (ref/*.png, ref.mjs; npm test -- theme-dom): each case of
// ref/cases.json rendered by DomFidelity.hx's bundle in a frame as ref.mjs
// draws it (800px wide, Inter, padding 16, animations and transitions off),
// its state forced on the component's main slot as ref.mjs forces it
// (hover, focus-visible through the DevTools protocol; the case's
// attributes set on it), a popup opened as the user would (a click, a
// right click, a hover, a key) and compared in its box, 8px around it.
// The same browser and the same CSS semantics: the bar is a mean
// difference under MEAN and at most MAX_FAR of the pixels FAR apart; the
// cases known to differ (KNOWN, each with its reason) are reported, not failed.
//   node tests/theme/dom-fidelity.mjs <dir: domfidelity.js, shadcn.css> [<out dir>]
import { createServer } from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const [dir, outDir] = process.argv.slice(2);
if (!dir) {
	console.error('usage: node dom-fidelity.mjs <dir> [<out dir>]');
	process.exit(2);
}
const MEAN = 1.0, FAR = 64, MAX_FAR = 0.005;
// the cases known to differ, by the start of their names, and why
const KNOWN = {
};
const known = name => Object.entries(KNOWN).find(([k]) => name.startsWith(k))?.[1];

// (a PNG's pixels as RGBA: 8-bit, RGB or RGBA, not interlaced, as Chromium writes them)
function png(buf) {
	let i = 8, w = 0, h = 0, type = 0;
	const idat = [];
	while (i < buf.length) {
		const len = buf.readUInt32BE(i), kind = buf.toString('ascii', i + 4, i + 8), data = buf.subarray(i + 8, i + 8 + len);
		if (kind === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); type = data[9]; if (data[8] !== 8 || data[12] !== 0) throw new Error('png: not 8-bit'); }
		else if (kind === 'IDAT') idat.push(data);
		i += 12 + len;
	}
	const bpp = type === 6 ? 4 : type === 2 ? 3 : (() => { throw new Error('png: colour type ' + type); })();
	const raw = zlib.inflateSync(Buffer.concat(idat)), stride = w * bpp, out = Buffer.alloc(w * h * 4);
	let prev = Buffer.alloc(stride);
	for (let y = 0; y < h; y++) {
		const f = raw[y * (stride + 1)], line = Buffer.from(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
		for (let x = 0; x < stride; x++) {
			const a = x >= bpp ? line[x - bpp] : 0, b = prev[x], c = x >= bpp ? prev[x - bpp] : 0;
			const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
			line[x] = (line[x] + [0, a, b, (a + b) >> 1, pa <= pb && pa <= pc ? a : pb <= pc ? b : c][f]) & 255;
		}
		for (let x = 0; x < w; x++) for (let k = 0; k < 4; k++) out[(y * w + x) * 4 + k] = k < bpp ? line[x * bpp + k] : 255;
		prev = line;
	}
	return { w, h, rgba: out };
}

// (ImageDiff's numbers: per pixel the largest channel difference)
function diff(a, b) {
	if (a.w !== b.w || a.h !== b.h) return { size: `${a.w}x${a.h}, want ${b.w}x${b.h}`, mean: 255, far: a.w * a.h, count: a.w * a.h };
	let total = 0, far = 0, differ = 0, max = 0;
	for (let p = 0; p < a.w * a.h; p++) {
		let d = 0;
		for (let k = 0; k < 3; k++) d = Math.max(d, Math.abs(a.rgba[p * 4 + k] - b.rgba[p * 4 + k]));
		total += d;
		if (d) differ++;
		if (d > FAR) far++;
		if (d > max) max = d;
	}
	return { mean: total / (a.w * a.h), far, differ, max, count: a.w * a.h };
}

const types = { '.js': 'text/javascript', '.css': 'text/css', '.html': 'text/html' };
const page0 = `<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="shadcn.css">
<style>*,*::before,*::after{animation:none!important;transition:none!important}</style></head>
<body style="margin:0"><div id="frame"></div><script src="domfidelity.js"></script></body></html>`;
const server = createServer((req, res) => {
	const p = new URL(req.url, 'http://x').pathname;
	try {
		const b = p === '/' ? Buffer.from(page0) : fs.readFileSync(path.join(dir, path.basename(p)));
		res.writeHead(200, { 'content-type': types[path.extname(p)] ?? 'text/html' });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
});
await new Promise(r => server.listen(0, r));
const url = `http://localhost:${server.address().port}/`;
const cases = JSON.parse(fs.readFileSync(path.join(here, 'ref/cases.json'), 'utf8'));
// (text unhinted and greyscale, as the references were drawn, whatever the machine's fontconfig says)
const browser = await pw.chromium.launch({ env: { ...process.env, FONTCONFIG_FILE: path.join(here, 'fonts.conf') } });
const page = await browser.newPage({ viewport: { width: 800, height: 600 }, deviceScaleFactor: 1 });
const errors = [];
page.on('pageerror', e => errors.push(e.message));
await page.goto(url);
await page.evaluate(() => document.fonts.ready);
const cdp = await page.context().newCDPSession(page);
await cdp.send('DOM.enable');
await cdp.send('CSS.enable');
// (the element a case's states and attributes are on: the component's main slot)
const TARGET = { 'input-group': 'input-group-control', 'radio-group': 'radio-group-item', slider: 'slider-thumb', tabs: 'tabs-trigger', select: 'select-trigger', 'dropdown-menu': 'dropdown-menu-item' };
if (outDir) fs.mkdirSync(outDir, { recursive: true });
let failed = 0, skipped = 0;
for (const c of cases) {
	const fw = c.fw ?? c.w, fh = c.fh ?? c.h;
	const ok = await page.evaluate(([c, fw, fh]) => window.renderCase(c, fw, fh), [c, fw, fh]);
	if (!ok) {
		console.log(`dom-fidelity: ${c.name} skipped (no widget for it)`);
		skipped++;
		continue;
	}
	const sel = `[data-slot=${TARGET[c.component] ?? c.component}]`;
	if (c.attrs) await page.evaluate(([sel, attrs]) => {
		const el = document.querySelector(sel);
		for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v === true ? '' : v);
	}, [sel, c.attrs]);
	// (what the user does: open a popup)
	const slot = s => page.locator(`[data-slot=${s}]`).first();
	switch (c.component) {
		case 'select-content': await slot('select-trigger').click(); break;
		case 'dropdown-menu': case 'dropdown-menu-items': case 'popover': await slot('button').click(); break;
		case 'menubar-content': await slot('menubar-trigger').click(); break;
		case 'context-menu': await page.locator('#area').click({ button: 'right', position: { x: 8, y: 8 } }); break;
		case 'tooltip': case 'hover-card': await slot('button').hover(); await page.waitForTimeout(800); break;
		case 'combobox': await slot('input').focus(); await page.keyboard.press('ArrowDown'); break;
		case 'input-otp': await page.locator('[data-slot=input-otp] input').focus(); break;
		case 'toast': await page.evaluate(([t, a]) => window.toast(t, a), [c.text, c.action]); break;
		case 'navigation-menu': if (c.crop) await slot('navigation-menu-trigger').click(); break;
		case 'chart-legend': await page.evaluate(() => { document.querySelector('[data-slot=chart-x-axis]').style.visibility = 'hidden'; }); break;
		case 'chart-tooltip': {
			// (the pointer over February's bars)
			const b = await slot('chart-plot').boundingBox();
			await page.mouse.move(b.x + b.width * 1.5 / 6, b.y + b.height / 2);
			break;
		}
	}
	if (c.component !== 'tooltip' && c.component !== 'hover-card' && c.component !== 'chart-tooltip') await page.mouse.move(799, 599);
	const { root } = await cdp.send('DOM.getDocument');
	const force = async (selector, states) => {
		const { nodeId } = await cdp.send('DOM.querySelector', { nodeId: root.nodeId, selector });
		if (nodeId) await cdp.send('CSS.forcePseudoState', { nodeId, forcedPseudoClasses: states.concat(states.includes('focus-visible') ? ['focus'] : []) });
	};
	if (c.states) await force(sel, c.states);
	await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
	let shot;
	if (c.crop) {
		// (a popup alone, as ref.mjs draws it: what it opens from hidden, toasts aside, which are in the frame)
		if (c.component !== 'toast' && !c.component.startsWith('chart-')) await page.evaluate(() => { for (const e of document.querySelectorAll('#frame > *')) e.style.visibility = 'hidden'; });
		const b = await page.locator(`[data-slot=${c.crop}]`).first().boundingBox({ timeout: 2000 }).catch(() => null);
		shot = b ? await page.screenshot({ clip: { x: Math.round(b.x) - 8, y: Math.round(b.y) - 8, width: c.w, height: c.h } }) : null;
	} else shot = await page.locator('#frame').screenshot();
	if (c.states) await force(sel, []);
	if (!shot) {
		console.log(`dom-fidelity: ${c.name} FAILED (no ${c.crop})`);
		failed++;
		continue;
	}
	if (outDir) fs.writeFileSync(path.join(outDir, c.name + '.png'), shot);
	const d = diff(png(shot), png(fs.readFileSync(path.join(here, 'ref', c.name + '.png'))));
	const good = d.mean < MEAN && d.far <= MAX_FAR * d.count, why = known(c.name);
	if (!good && !why) failed++;
	const verdict = why ? (good ? `ok, though known to differ (${why})` : `differs, as known (${why})`) : good ? 'ok' : 'FAILED';
	const numbers = d.size ? `size ${d.size}` : d.differ === 0 ? 'exact' : `${d.differ} pixels differ, ${d.far} by more than ${FAR}, at most ${d.max}, mean ${d.mean.toFixed(2)}`;
	console.log(`dom-fidelity: ${c.name} ${verdict} (${numbers})`);
}
await browser.close();
server.close();
for (const e of errors) console.log(`dom-fidelity: page error: ${e}`);
console.log(`dom-fidelity: ${cases.length - skipped} cases (${skipped} without a widget)` + (failed || errors.length ? `, ${failed} FAILED` : ', ok'));
process.exit(failed || errors.length ? 1 : 0);
