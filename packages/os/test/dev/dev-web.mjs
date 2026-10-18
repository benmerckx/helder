// The dev loop in the browser (make dev-check; docs/dev.md): `hxmc dev` on a
// copy of @hxmc/ui's Counter example (packages/ui/examples/Counter.hx, with
// a line printing its count), in headless Chromium:
// - the counter clicked three times (its button in the canvas's ARIA mirror);
// - an edit (the button's label, what it prints): the page reloads with the
//   new build, the count still 3;
// - the signal's type changed (Int to Float): reset to its new value, logged;
// - a compile error: the overlay shows it, the last good build keeps running
//   (the page not reloaded, the counter still counts); fixed: the new build,
//   the count kept;
// - the reloads' times, from the change seen to the new build's first frame.
//   node packages/os/test/dev/dev-web.mjs <compiler> [work dir]
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../../../..');
const compiler = path.resolve(process.argv[2] ?? 'bin/hxmc/hxmc');
const work = path.resolve(process.argv[3] ?? fs.mkdtempSync(path.join(os.tmpdir(), 'hxmc-dev-web-')));
const CHROMIUM_ARGS = ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'];

let failures = 0;
const check = (what, ok, detail = '') => {
	console.log((ok ? 'ok   ' : 'FAIL ') + what + (ok || !detail ? '' : ': ' + detail));
	if (!ok) failures++;
};

// the program: Counter, printing its count (count=<n>, its prefix the version)
fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(path.join(work, 'app'), { recursive: true });
const counter = path.join(work, 'app', 'Counter.hx');
const original = fs.readFileSync(path.join(repo, 'packages/ui/examples/Counter.hx'), 'utf8');
const v1 = original.replace('var count = signal(0);', 'var count = signal(0);\n\t\teffect(() -> trace("v1 count=" + count.value));');
if (v1 === original) throw new Error('Counter.hx changed: its signal line is not found');
fs.writeFileSync(counter, v1);
const cp = ['os', 'gfx', 'text', 'view', 'ui', 'theme'].map((p) => `-cp ${path.join(repo, 'packages', p, 'src')}`);
fs.writeFileSync(path.join(work, 'build.hxml'), ['-cp app', ...cp, '-D hxmc.view.renderer.ui=hxmc.ui.view.NodeRenderer', '-main Counter',
	'-D hxmc.target=wasm32-wasi', '--custom-target hxmc=out/counter.wasm'].join('\n') + '\n');
const edit = (f) => fs.writeFileSync(counter, f(fs.readFileSync(counter, 'utf8')));

const port = await new Promise((r) => {
	const s = net.createServer().listen(0, () => {
		const p = s.address().port;
		s.close(() => r(p));
	});
});
const lines = [];
const waiters = [];
const dev = spawn(process.execPath, [path.join(repo, 'packages/cli/hxmc/bootstrap/dev.mjs'), compiler, '--port', String(port), 'build.hxml'],
	{ cwd: work, stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, HAXE_STD_PATH: process.env.HAXE_STD_PATH ?? path.join(repo, 'haxe/upstream/std') } });
const onLine = (l) => {
	lines.push(l);
	if (process.env.DEV_VERBOSE) console.log('  | ' + l);
	for (const w of [...waiters]) if (w.re.test(l)) {
		waiters.splice(waiters.indexOf(w), 1);
		w.resolve(l);
	}
};
for (const s of [dev.stdout, dev.stderr]) {
	let buf = '';
	s.on('data', (d) => {
		buf += d;
		let nl;
		while ((nl = buf.indexOf('\n')) >= 0) {
			onLine(buf.slice(0, nl));
			buf = buf.slice(nl + 1);
		}
	});
}
// the next line of the dev server's matching re (from now on)
const line = (re, ms = 120000) => new Promise((resolve, reject) => {
	const t = setTimeout(() => reject(new Error('timed out waiting for ' + re + '; the last lines:\n' + lines.slice(-30).join('\n'))), ms);
	waiters.push({ re, resolve: (l) => { clearTimeout(t); resolve(l); } });
});

const browser = await pw.chromium.launch({ args: CHROMIUM_ARGS });
const times = [];
try {
	await line(/^hxmc dev: built in/);
	const page = await browser.newPage();
	page.on('pageerror', (e) => console.log('page error: ' + e.message));
	await page.goto(`http://localhost:${port}/`);
	// the page's printed lines (since it last loaded)
	const printed = () => page.evaluate(() => window.hxmcDev?.log ?? []);
	const until = async (re, what, ms = 60000) => {
		const end = Date.now() + ms;
		for (;;) {
			const log = await printed().catch(() => []);
			const hit = log.find((l) => re.test(l));
			if (hit) return hit;
			if (Date.now() > end) throw new Error(`${what}: no ${re} in ${JSON.stringify(log)}`);
			await page.waitForTimeout(50);
		}
	};
	const count = async (version, n, what) => check(what, !!(await until(new RegExp(`${version} count=${n}$`), what).catch((e) => (console.log(e.message), null))));
	const click = () => page.evaluate(() => document.querySelector('canvas [role=button]').click());

	await count('v1', 0, 'the first build runs');
	await page.waitForFunction(() => document.querySelector('canvas [role=button]'));
	for (let i = 0; i < 3; i++) await click();
	await count('v1', 3, 'clicked three times');

	// an edit: the new code, the state kept
	const reloaded = line(/^hxmc dev: reloaded in/);
	edit((s) => s.replace('label="+1"', 'label="+2"').replace('"v1 count="', '"v2 count="'));
	times.push(await reloaded);
	await count('v2', 3, 'edited: the new build, the count kept');
	check('the new label', await page.evaluate(() => !!document.querySelector('canvas [role=button][aria-label="+2"]') || [...document.querySelectorAll('canvas [role=button]')].some((b) => b.textContent.includes('+2'))));

	// the signal's type changed: reset to its new initial value, and said so
	const reloaded2 = line(/^hxmc dev: reloaded in/);
	const reset = line(/Counter\.main\.count reset: its type changed/);
	edit((s) => s.replace('signal(0)', 'signal(0.5)').replace('"v2 count="', '"v3 count="'));
	times.push(await reloaded2);
	check('type changed: logged', !!(await reset.catch(() => null)));
	await count('v3', 0.5, 'type changed: reset');
	await click();
	await count('v3', 1.5, 'counting again');

	// a compile error: the overlay, the last good build still running
	await page.evaluate(() => (window.hxmcDevMarker = 'still the same page'));
	const failed = line(/^hxmc dev: error/);
	edit((s) => s.replace('"v3 count="', '"v4 count=" +* broken'));
	await failed;
	await page.waitForFunction(() => getComputedStyle(document.getElementById('hxmc-dev-overlay')).display !== 'none', null, { timeout: 30000 }).catch(() => {});
	const overlay = await page.evaluate(() => ({ shown: getComputedStyle(document.getElementById('hxmc-dev-overlay')).display !== 'none', text: document.getElementById('hxmc-dev-overlay').textContent }));
	check('error: the overlay shows it', overlay.shown && /Counter\.hx/.test(overlay.text), overlay.text.slice(0, 300));
	check('error: the page is the same', (await page.evaluate(() => window.hxmcDevMarker)) === 'still the same page');
	await click();
	await count('v3', 2.5, 'error: the last good build keeps running');

	// fixed: the new build, the state kept, the overlay gone
	const reloaded3 = line(/^hxmc dev: reloaded in/);
	edit((s) => s.replace('"v4 count=" +* broken', '"v5 count="'));
	times.push(await reloaded3);
	await count('v5', 2.5, 'fixed: the new build, the count kept');
	check('fixed: no overlay', await page.evaluate(() => getComputedStyle(document.getElementById('hxmc-dev-overlay')).display === 'none'));
} catch (e) {
	console.log('FAIL ' + e.message);
	failures++;
} finally {
	await browser.close();
	dev.kill();
}
for (const t of times) console.log('  ' + t);
console.log(failures === 0 ? 'dev-web: ok' : `dev-web: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
