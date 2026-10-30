// The dev loop in the browser (npm test -- dev; docs/dev.md): `hxmc dev` on a
// copy of helder.ui's Counter example (examples/counter/Counter.hx, with
// a line printing its count), in headless Chromium:
// - the counter clicked three times (its button in the canvas's ARIA mirror);
// - an edit (the button's label, what it prints): the new build swapped in,
//   the count still 3;
// - the signal's type changed (Int to Float): reset to its new value, logged;
// - a compile error: the overlay shows it, the last good build keeps running
//   (the page not reloaded, the counter still counts); fixed: the new build,
//   the count kept;
// - no reload, ever: after each swap the page is the same (a marker set on
//   window survives, no navigation: Playwright's and the Performance API's),
//   the canvas and the GPU device (WebGPU's GPUDevice; on a second page with
//   ?gfx=webgl2, the canvas's WebGL2 context) are the same objects, there is
//   one canvas, and the old build left no GPU objects;
// - the swaps' times, from the change seen to the new build's first frame.
//   node tests/os/dev/dev-web.mjs <compiler> [work dir] [--helder=<exe>]
// (--helder: `helder dev app/Counter.hx --target web` instead of dev.mjs, its build
// not compared with a fresh one)
import { spawn, spawnSync } from 'node:child_process';
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
const repo = path.resolve(here, '../../..');
const compiler = path.resolve(process.argv.slice(2).find((a) => !a.startsWith('--')) ?? 'node_modules/.bin/haxe');
const helder = process.argv.find((a) => a.startsWith('--helder='))?.slice(9);
const positional = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const work = path.resolve(positional[1] ?? fs.mkdtempSync(path.join(os.tmpdir(), 'hxmc-dev-web-')));
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
const original = fs.readFileSync(path.join(repo, 'examples/counter/Counter.hx'), 'utf8');
const v1 = original.replace('var count = signal(0);', 'var count = signal(0);\n\t\teffect(() -> count(), v -> trace("v1 count=" + v));');
if (v1 === original) throw new Error('Counter.hx changed: its signal line is not found');
fs.writeFileSync(counter, v1);
const cp = [`-cp ${path.join(repo, 'src')}`];
fs.writeFileSync(path.join(work, 'build.hxml'), ['-cp app', ...cp, '-main Counter',
	'-D hxmc.target=wasm32-wasi', '--custom-target hxmc=out/counter.wasm'].join('\n') + '\n');
// (written beside and renamed over: the watcher never reads a half-written file)
const edit = (f) => { fs.writeFileSync(counter + '.tmp', f(fs.readFileSync(counter, 'utf8'))); fs.renameSync(counter + '.tmp', counter); };

const port = await new Promise((r) => {
	const s = net.createServer().listen(0, () => {
		const p = s.address().port;
		s.close(() => r(p));
	});
});
const lines = [];
const waiters = [];
const dev = helder ? spawn(path.resolve(helder), ['dev', 'app/Counter.hx', '--target', 'web', '--port', String(port)], { cwd: work, stdio: ['ignore', 'pipe', 'pipe'] })
	: spawn(process.execPath, [path.join(repo, 'node_modules/@hxmc/cli/hxmc/bootstrap/dev.mjs'), compiler, '--port', String(port), 'build.hxml'],
		{ cwd: work, stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env } });
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
const line = (re, ms = 120000) => {
	const pr = new Promise((resolve, reject) => {
		const t = setTimeout(() => reject(new Error('timed out waiting for ' + re + '; the last lines:\n' + lines.slice(-30).join('\n'))), ms);
		waiters.push({ re, resolve: (l) => { clearTimeout(t); resolve(l); } });
	});
	// (handled when awaited; one not awaited yet must not end the run)
	pr.catch(() => {});
	return pr;
};

const browser = await pw.chromium.launch({ args: CHROMIUM_ARGS });
const times = [];
try {
	if (!lines.some((l) => /^(?:(?:hxmc|helder) dev: |\s*)built in/.test(l))) await line(/^(?:(?:hxmc|helder) dev: |\s*)built in/);
	const page = await browser.newPage();
	page.on('pageerror', (e) => console.log('page error: ' + e.message + (process.env.DEV_VERBOSE ? '\n' + e.stack : '')));
	// (navigations of the main frame after the first: a reload)
	const navigations = new Map();
	const watchNavigation = (p) => p.on('framenavigated', (f) => f === p.mainFrame() && navigations.set(p, (navigations.get(p) ?? 0) + 1));
	watchNavigation(page);
	await page.goto(`http://localhost:${port}/`);
	// a second page on WebGL2 (its own state)
	const gl = await browser.newPage();
	gl.on('pageerror', (e) => console.log('page error (webgl2): ' + e.message));
	watchNavigation(gl);
	await gl.goto(`http://localhost:${port}/?gfx=webgl2`);
	// what must stay across swaps: set after the first build's first frame
	const remember = (p) => p.evaluate(() => {
		window.hxmcDevMarker = 'the same page';
		window.hxmcDevFirst = { device: window.hxmcDev.gpu?.device ?? null, canvas: window.hxmcDev.canvas,
			gl: window.hxmcDev.canvas?.getContext('webgl2') ?? null, navigation: performance.getEntriesByType('navigation').length, timeOrigin: performance.timeOrigin };
	});
	const same = async (p, what, swaps) => {
		const r = await p.evaluate(() => {
			const f = window.hxmcDevFirst, d = window.hxmcDev;
			return { marker: window.hxmcDevMarker, swaps: d.swaps, canvas: d.canvas === f.canvas && document.querySelectorAll('canvas').length === 1,
				device: d.gpu?.device ?? null, sameDevice: (d.gpu?.device ?? null) === f.device, gl: f.gl === null || d.canvas.getContext('webgl2') === f.gl,
				navigation: performance.getEntriesByType('navigation').length === f.navigation && performance.timeOrigin === f.timeOrigin, left: d.left ?? 0 };
		});
		check(`${what}: no reload (the same page, ${r.swaps} swaps)`, r.marker === 'the same page' && r.navigation && (navigations.get(p) ?? 0) === 1 && r.swaps >= swaps, JSON.stringify(r));
		check(`${what}: the same canvas and GPU device (or WebGL2 context)`, r.canvas && r.sameDevice && r.gl, JSON.stringify(r));
		check(`${what}: the old build released its GPU objects`, r.left === 0, JSON.stringify(r));
	};
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
	await gl.waitForFunction(() => document.querySelector('canvas [role=button]'));
	await page.waitForFunction(() => window.hxmcDev.frames > 0);
	await gl.waitForFunction(() => window.hxmcDev.frames > 0);
	check('WebGPU on the first page', await page.evaluate(() => !!window.hxmcDev.gpu), 'no GPUDevice: WebGPU not tested');
	await remember(page);
	await remember(gl);
	await gl.evaluate(() => document.querySelector('canvas [role=button]').click());
	for (let i = 0; i < 3; i++) await click();
	await count('v1', 3, 'clicked three times');

	// an edit: the new code, the state kept
	const reloaded = line(/^(?:(?:hxmc|helder) dev: |\s*)(?:swapped|reloaded) in/);
	edit((s) => s.replace('label="+1"', 'label="+2"').replace('>+1<', '>+2<').replace('"v1 count="', '"v2 count="'));
	times.push(await reloaded);
	await count('v2', 3, 'edited: the new build, the count kept');
	check('the new label', await page.evaluate(() => !!document.querySelector('canvas [role=button][aria-label="+2"]') || [...document.querySelectorAll('canvas [role=button]')].some((b) => b.textContent.includes('+2'))));
	await same(page, 'edited', 1);
	// (the WebGL2 page: its own count, 1, kept)
	const glCount = async (version, n, what) => {
		const end = Date.now() + 30000;
		while (Date.now() < end) {
			if ((await gl.evaluate(() => window.hxmcDev.log)).some((l) => l.endsWith(`${version} count=${n}`))) return check(what, true);
			await gl.waitForTimeout(50);
		}
		check(what, false, JSON.stringify((await gl.evaluate(() => window.hxmcDev.log)).slice(-5)));
	};
	await glCount('v2', 1, 'edited, WebGL2: the count kept');
	await same(gl, 'edited, WebGL2', 1);

	// the signal's type changed: reset to its new initial value, and said so
	const reloaded2 = line(/^(?:(?:hxmc|helder) dev: |\s*)(?:swapped|reloaded) in/);
	const reset = line(/Counter\.main\.count reset: its type changed/);
	edit((s) => s.replace('signal(0)', 'signal(0.5)').replace('"v2 count="', '"v3 count="'));
	times.push(await reloaded2);
	check('type changed: logged', !!(await reset.catch(() => null)));
	await count('v3', 0.5, 'type changed: reset');
	await click();
	await count('v3', 1.5, 'counting again');

	// a compile error: the overlay, the last good build still running
	await page.evaluate(() => (window.hxmcDevMarker = 'still the same page'));
	const failed = line(/^(?:(?:hxmc|helder) dev: error|\s*failed in)/);
	edit((s) => s.replace('"v3 count="', '"v4 count=" +* broken'));
	await failed;
	await page.waitForFunction(() => getComputedStyle(document.getElementById('hxmc-dev-overlay')).display !== 'none', null, { timeout: 30000 }).catch(() => {});
	const overlay = await page.evaluate(() => ({ shown: getComputedStyle(document.getElementById('hxmc-dev-overlay')).display !== 'none', text: document.getElementById('hxmc-dev-overlay').textContent }));
	check('error: the overlay shows it', overlay.shown && /Counter\.hx/.test(overlay.text), overlay.text.slice(0, 300));
	check('error: the page is the same', (await page.evaluate(() => window.hxmcDevMarker)) === 'still the same page');
	await page.evaluate(() => (window.hxmcDevMarker = 'the same page'));
	await click();
	await count('v3', 2.5, 'error: the last good build keeps running');

	// fixed: the new build, the state kept, the overlay gone
	const reloaded3 = line(/^(?:(?:hxmc|helder) dev: |\s*)(?:swapped|reloaded) in/);
	edit((s) => s.replace('"v4 count=" +* broken', '"v5 count="'));
	times.push(await reloaded3);
	await count('v5', 2.5, 'fixed: the new build, the count kept');
	await same(page, 'fixed', 3);
	await glCount('v5', 0.5, 'fixed, WebGL2: the count kept');
	await same(gl, 'fixed, WebGL2', 3);
	check('fixed: no overlay', await page.evaluate(() => getComputedStyle(document.getElementById('hxmc-dev-overlay')).display === 'none'));
} catch (e) {
	console.log('FAIL ' + e.message);
	failures++;
} finally {
	await browser.close();
	dev.kill();
}
// the dev server's last build (its compilation server reusing typed modules,
// lowered bodies and objects across the edits) is what a fresh build makes
const devOut = path.join(work, 'out/counter.wasm');
if (failures === 0 && !helder && fs.existsSync(devOut)) {
	const kept = fs.readFileSync(devOut);
	const std = path.join(path.dirname(compiler), 'std');
	const r = spawnSync(compiler, ['-D', 'hxmc.dev', 'build.hxml', ...(fs.existsSync(std) ? ['-cp', std] : [])],
		{ cwd: work, encoding: 'utf8', env: { ...process.env, HXMC_MODULE_CACHE: '0' } });
	check('the last build is a fresh build, byte for byte', r.status === 0 && Buffer.compare(kept, fs.readFileSync(devOut)) === 0, (r.stderr ?? '').slice(-800));
}
for (const t of times) console.log('  ' + t);
const name = 'dev-web';
console.log(failures === 0 ? `${name}: ok` : `${name}: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
