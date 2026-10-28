// helder dev's asset reload in the browser (the dev lane): `helder dev
// app/Swatch.hx --target web` (tests/cli/swatch: an image and a text loaded
// by path, helder.asset) in headless Chromium; a new PNG written over the
// image is sent to the page ({"type":"asset"}), which hands the key to the
// running module: it fetches /__hxmc/assets/swatch.png and puts the new
// pixels in the same Image (its line in the page's log says so), with no
// build, no swap and no navigation; then the text, its reader run again.
//   node tests/os/dev/dev-asset.mjs <helder> <work dir>
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../../..');
const [helder, workDir] = process.argv.slice(2);
const work = path.resolve(workDir);
let failures = 0;
const check = (what, ok, detail = '') => {
	console.log((ok ? 'ok   ' : 'FAIL ') + what + (ok || !detail ? '' : ': ' + detail));
	if (!ok) failures++;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// (an RGBA8 PNG of w x h pixels, each rgba)
const png = (w, h, rgba) => {
	const chunk = (t, d) => {
		const b = Buffer.alloc(12 + d.length);
		b.writeUInt32BE(d.length, 0);
		b.write(t, 4, 'latin1');
		d.copy(b, 8);
		b.writeUInt32BE(zlib.crc32(b.subarray(4, 8 + d.length)), 8 + d.length);
		return b;
	};
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(w, 0);
	ihdr.writeUInt32BE(h, 4);
	ihdr.set([8, 6, 0, 0, 0], 8);
	const rows = Buffer.alloc(h * (1 + 4 * w));
	for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) rows.writeUInt32BE(rgba, y * (1 + 4 * w) + 1 + 4 * x);
	return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(rows)), chunk('IEND', Buffer.alloc(0))]);
};
const write = (name, data) => {
	const f = path.join(work, 'app', name);
	fs.writeFileSync(f + '.tmp', data);
	fs.renameSync(f + '.tmp', f);
};

fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(path.join(work, 'app'), { recursive: true });
fs.copyFileSync(path.join(repo, 'tests/cli/swatch/Swatch.hx'), path.join(work, 'app/Swatch.hx'));
write('swatch.png', png(2, 2, 0xff0000ff));
write('note.txt', 'first note\n');

const lines = [];
const dev = spawn(path.resolve(helder), ['dev', 'app/Swatch.hx', '--target', 'web', '--port', '0'], { cwd: work, stdio: ['ignore', 'pipe', 'pipe'] });
for (const s of [dev.stdout, dev.stderr]) {
	let buf = '';
	s.on('data', (d) => {
		buf += d;
		let nl;
		while ((nl = buf.indexOf('\n')) >= 0) {
			lines.push(buf.slice(0, nl));
			if (process.env.DEV_VERBOSE) console.log('  | ' + buf.slice(0, nl));
			buf = buf.slice(nl + 1);
		}
	});
}
const until = async (f, what, ms = 60000) => {
	for (const end = Date.now() + ms; Date.now() < end; await sleep(20)) {
		const v = await f();
		if (v) return v;
	}
	throw new Error('timed out: ' + what + '; the last lines:\n' + lines.slice(-15).join('\n'));
};

const browser = await pw.chromium.launch({ args: ['--use-angle=swiftshader'] });
try {
	const at = await until(() => lines.map((l) => /http:\/\/127\.0\.0\.1:(\d+)\//.exec(l)).find((m) => m), 'serving', 30000);
	await until(() => lines.some((l) => /^\s*built in/.test(l)), 'the first build', 240000);
	const page = await browser.newPage();
	page.on('console', (m) => process.env.DEV_VERBOSE && console.log('  page| ' + m.text()));
	await page.goto(`http://127.0.0.1:${at[1]}/`);
	const log = () => page.evaluate(() => window.hxmcDev?.log ?? []);
	const has = (re) => async () => (await log()).find((l) => re.test(l));
	check('the first build: the image', !!(await until(has(/^swatch: 2x2 px ff0000ff version 0 same image$/), 'the first image')));
	check('the first build: the text', !!(await until(has(/^note: first note$/), 'the first text')));
	await page.evaluate(() => (window.hxmcDevMarker = 'the same page'));
	const t0 = performance.now();
	write('swatch.png', png(3, 1, 0x00ff00ff));
	const l = await until(has(/^swatch: 3x1 px 00ff00ff version \d+ (same|another) image$/), 'the new image');
	const ms = Math.round(performance.now() - t0);
	check(`the new image in the same Image object (${ms} ms from the save)`, l.endsWith('same image'), l);
	write('note.txt', 'second note\n');
	check('the text: its reader ran again', !!(await until(has(/^note: second note$/), 'the new text')));
	const state = await page.evaluate(() => ({ marker: window.hxmcDevMarker, swaps: window.hxmcDev.swaps, assets: window.hxmcDev.assets }));
	check('no navigation, no swap: the same page and module', state.marker === 'the same page' && state.swaps === 0, JSON.stringify(state));
	check('the page took two changed assets', state.assets === 2, JSON.stringify(state));
	check('no build for an asset', !lines.some((l) => /^\s*rebuilt in/.test(l)));
} catch (e) {
	check(e.message, false);
} finally {
	await browser.close();
	dev.kill();
}
console.log(failures === 0 ? 'dev asset web: ok' : `dev asset web: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
