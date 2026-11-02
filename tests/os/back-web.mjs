// App.onBack and App.backDepth in headless Chromium (bun run test
// touch-web): BackWeb.wasm on a page that came after another (/start), its
// lines and history.length checked: one entry of the page's own while deep,
// whatever the depth; history back a step up while deep, the entry kept
// until the last step, then gone; at depth 0 back the page's own (back to
// /start); the entry gone again when the app is no longer deep by itself.
//   node tests/os/back-web.mjs <BackWeb.wasm>
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
const page = `<!doctype html><title>BackWeb</title><body style="margin:0">
<canvas id="c" style="width: 200px; height: 100px; display: block"></canvas>
<script type="module">
import { run } from './os/browser.mjs';
window.log = [];
window.started = run('test.wasm', { imports: ['os/imports.mjs'], canvas: 'c', stdout: (s) => window.log.push(s), stderr: (s) => window.log.push('stderr: ' + s) });
</script>`;
const server = createServer(async (req, res) => {
	const p = new URL(req.url, 'http://x').pathname;
	try {
		const b = p === '/' ? Buffer.from(page) : p === '/start' ? Buffer.from('<!doctype html><title>start</title>') : await readFile(files[p]);
		res.writeHead(200, { 'content-type': p === '/' || p === '/start' ? 'text/html' : types[path.extname(p)] });
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
	console.log(`back-web.mjs: ${ok ? 'ok' : 'FAIL'}: ${what}${ok ? '' : ': ' + detail}`);
};
try {
	const ctx = await browser.newContext();
	const p = await ctx.newPage();
	const base = `http://localhost:${server.address().port}`;
	await p.goto(`${base}/start`);
	await p.goto(`${base}/`);
	await p.evaluate(() => window.started);
	const settle = () => p.waitForTimeout(200);
	let seen = 0;
	const lines = async () => {
		await settle();
		const all = await p.evaluate(() => window.log);
		const out = all.slice(seen);
		seen = all.length;
		return out;
	};
	const length = () => p.evaluate(() => history.length);
	// (history back as the browser's button does it, without the page's code)
	const back = async () => {
		const cdp = await ctx.newCDPSession(p);
		const { currentIndex, entries } = await cdp.send('Page.getNavigationHistory');
		await cdp.send('Page.navigateToHistoryEntry', { entryId: entries[currentIndex - 1].id });
		await cdp.detach();
	};
	const first = await lines();
	check('haxe.Timer.delay: fired, and one made in its callback', first.includes('timer 1') && first.indexOf('timer 2') > first.indexOf('timer 1'), first.join(' / '));
	const start = await length();
	await p.click('#c');
	await p.keyboard.press('d');
	let l = await lines();
	check('deep: one entry of its own', l.includes('depth 1') && (await length()) === start + 1, l.join(' / ') + ' length ' + (await length()));
	await p.keyboard.press('d');
	await p.keyboard.press('d');
	l = await lines();
	check('deeper: still the one entry', l.includes('depth 3') && (await length()) === start + 1, l.join(' / ') + ' length ' + (await length()));
	await back();
	l = await lines();
	check('back: onBack, a step up, the entry again', l.includes('back 2') && (await p.evaluate(() => history.state?.helderBack)) === 1 && p.url() === `${base}/`, l.join(' / '));
	await back();
	l = await lines();
	check('back again: a step up', l.includes('back 1') && (await p.evaluate(() => history.state?.helderBack)) === 1, l.join(' / '));
	await back();
	l = await lines();
	check('the last step: depth 0, no entry of its own', l.includes('back 0') && (await p.evaluate(() => history.state)) == null && p.url() === `${base}/`, l.join(' / '));
	// deep again, then up by the app itself: the entry taken away
	await p.keyboard.press('d');
	await lines();
	check('deep again: its entry on top', (await p.evaluate(() => history.state?.helderBack)) === 1, '');
	await p.keyboard.press('h');
	l = await lines();
	check('home by the app: its entry gone, onBack not asked', l.includes('depth 0') && !l.some((s) => s.startsWith('back')) && (await p.evaluate(() => history.state)) == null && p.url() === `${base}/`, l.join(' / '));
	await p.keyboard.press('d');
	await p.keyboard.press('h');
	await p.keyboard.press('d');
	l = await lines();
	check('deep, home and deep at once: one entry on top', l.includes('depth 1') && (await p.evaluate(() => history.state?.helderBack)) === 1, l.join(' / '));
	await back();
	l = await lines();
	check('back to depth 0 again', l.includes('back 0'), l.join(' / '));
	// Escape: the back, onBack's; not taken (depth 0), the app's key; while
	// text is typed, the text's
	await p.keyboard.press('d');
	await lines();
	await p.keyboard.press('Escape');
	l = await lines();
	check('Escape: onBack, a step up, not the app\'s key', l.includes('back 0') && !l.includes('key escape') && (await p.evaluate(() => history.state)) == null, l.join(' / '));
	await p.keyboard.press('Escape');
	l = await lines();
	check('Escape at depth 0: onBack not taking it, the app\'s key', l.includes('back 0 home') && l.includes('key escape'), l.join(' / '));
	await p.keyboard.press('t');
	await p.keyboard.press('d');
	await p.keyboard.press('Escape');
	l = await lines();
	check('Escape while typing: the text\'s, onBack not asked', l.includes('typing true') && l.includes('key escape') && !l.some((s) => s.startsWith('back')), l.join(' / '));
	await p.keyboard.press('t');
	await p.keyboard.press('Escape');
	l = await lines();
	check('typing off: Escape onBack\'s again', l.includes('typing false') && l.includes('back 0') && !l.includes('key escape'), l.join(' / '));
	const errors = (await p.evaluate(() => window.log)).filter((s) => s.startsWith('stderr'));
	check('no errors', errors.length === 0, errors.join(' / '));
	// at depth 0: the page's own back, onBack not asked
	await back();
	await settle();
	check('at depth 0: the page left (back to /start)', p.url() === `${base}/start`, p.url());
} finally {
	await browser.close();
	server.close();
}
if (failed > 0) {
	console.log(`back-web.mjs: ${failed} FAILED`);
	process.exit(1);
}
console.log('back-web.mjs: ok');
