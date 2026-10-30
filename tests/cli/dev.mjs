// `helder dev` without a window or a browser (the cli lane):
// - native: tests/cli/tally (a console program whose count helder.dev.Hot
//   keeps) copied into the work directory; edits reload it with its count
//   (on Linux in the dev host: the same process), a broken edit keeps the
//   last good build running, the fix applies;
// - web: examples/counter's Counter.hx copied there, served: the page, its
//   modules and the wasm fetched, the WebSocket (node's client) told of each
//   build (reload, error, ok), a swap after a failed build refused (409).
// - native-nohost: native with HELDER_DEV_HOST=0, a process per build (each
//   reload's program exits 0 by itself: not a close);
// - exit: tests/cli/closer, a program that ends by itself (ExitPolicy):
//   with exit code 3 a crash, helder dev stays up; an edit makes it 0, the
//   program closed: helder dev ends, exit code 0.
// - asset, asset-nohost: tests/cli/swatch, an image and a text loaded by
//   path (helder.asset): a new PNG written over the image is sent, nothing
//   built, the same Image object then has its size and pixels; a new text
//   runs its reader again; an edit to the source still builds;
// - asset-web: Swatch for web: a new PNG sent to the page ({"type":
//   "asset"}), the dev server serving the new bytes at /__hxmc/assets/.
// The times from a save to the reload (native: the program's first frame,
// "reloaded in"; web: the reload message), each edit's, and their median.
//   node tests/cli/dev.mjs <helder> <work dir> native|native-nohost|web|exit
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import zlib from 'node:zlib';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [helder, work, mode] = process.argv.slice(2);
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let failures = 0;
const check = (what, ok, detail = '') => {
	console.log((ok ? 'ok   ' : 'FAIL ') + what + (ok || !detail ? '' : ': ' + detail));
	if (!ok) failures++;
};

fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(path.join(work, 'app'), { recursive: true });
const assets = mode.startsWith('asset'), web = mode === 'web' || mode === 'asset-web', exit = mode === 'exit';
const fixture = assets ? 'tests/cli/swatch/Swatch.hx' : web ? 'examples/counter/Counter.hx' : exit ? 'tests/cli/closer/Closer.hx' : 'tests/cli/tally/Tally.hx';
const file = path.join(work, 'app', path.basename(fixture));
fs.copyFileSync(path.join(repo, fixture), file);
// (an RGBA8 PNG of w x h pixels, each rgba: what Swatch loads)
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
// (written beside and renamed over, as editors save)
const write = (name, data) => {
	const f = path.join(work, 'app', name);
	fs.writeFileSync(f + '.tmp', data);
	fs.renameSync(f + '.tmp', f);
	return performance.now();
};
if (assets) {
	write('swatch.png', png(2, 2, 0xff0000ff));
	write('note.txt', 'first note\n');
}
const edit = (f) => {
	const s = fs.readFileSync(file, 'utf8'), t = f(s);
	if (t === s) throw new Error('the edit changed nothing');
	// (written beside and renamed over: the watcher never reads a half-written file)
	fs.writeFileSync(file + '.tmp', t);
	fs.renameSync(file + '.tmp', file);
	return performance.now();
};

const lines = [];
const waiters = [];
const dev = spawn(path.resolve(helder), ['dev', path.relative(work, file), ...(web ? ['--target', 'web', '--port', '0'] : [])],
	{ cwd: work, stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, ...(mode === 'native-nohost' || mode === 'asset-nohost' ? { HELDER_DEV_HOST: '0' } : {}) } });
const ended = new Promise((r) => dev.on('exit', (code, signal) => r(code ?? signal)));
const closed = (l) => /^\s*closed /.test(l);
for (const s of [dev.stdout, dev.stderr]) {
	let buf = '';
	s.on('data', (d) => {
		buf += d;
		let nl;
		while ((nl = buf.indexOf('\n')) >= 0) {
			const l = buf.slice(0, nl);
			buf = buf.slice(nl + 1);
			lines.push(l);
			if (process.env.DEV_VERBOSE) console.log('  | ' + l);
			for (const w of [...waiters]) if (w.re.test(l)) {
				waiters.splice(waiters.indexOf(w), 1);
				w.resolve(l);
			}
		}
	});
}
// the next line matching re (or one printed already, with past)
const line = (re, ms = 120000, past = false) => {
	const l = past && lines.find((x) => re.test(x));
	if (l) return Promise.resolve(l);
	const pr = new Promise((resolve, reject) => {
		const t = setTimeout(() => reject(new Error('timed out waiting for ' + re + '; the last lines:\n' + lines.slice(-20).join('\n'))), ms);
		waiters.push({ re, resolve: (x) => { clearTimeout(t); resolve(x); } });
	});
	pr.catch(() => {});
	return pr;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const median = (xs) => [...xs].sort((a, b) => a - b)[xs.length >> 1];
const times = [];

async function native() {
	const count = (l) => Number(/count=(\d+)/.exec(l)[1]);
	const first = await line(/^v1 count=2$/, 240000, true);
	check('the first build runs', !!first);
	const pids = () => lines.filter((l) => l.startsWith('start pid=')).map((l) => l.slice(10));
	const hosted = pids().length > 0;
	// (each edit: a new version, its count where the last one's was)
	for (let v = 2; v <= 4; v++) {
		await sleep(300);
		const before = count(lines.filter((l) => /^v\d+ count=/.test(l)).at(-1));
		const reloaded = line(/^\s*reloaded in/), next = line(new RegExp(`^v${v} count=`));
		const t0 = edit((s) => s.replace(`"v${v - 1} count="`, `"v${v} count="`));
		await reloaded;
		times.push(performance.now() - t0);
		const n = count(await next);
		check(`edit ${v - 1}: the new build, the count kept (${before} then ${n})`, n >= before && n <= before + 10);
	}
	if (hosted) check(`the dev host: the same process (${pids().length} builds)`, pids().length >= 4 && pids().every((p) => p === pids()[0]), pids().join(' '));
	const failed = line(/^\s*failed in/);
	edit((s) => s.replace('"v4 count="', '"v5 count=" +* broken'));
	await failed;
	check('broken: the error in the terminal', lines.some((l) => /Tally\.hx:\d+: characters/.test(l)));
	const still = await line(/^v4 count=/, 5000).catch(() => null);
	check('broken: the last good build keeps running', !!still && !lines.some((l) => /^\s*(?:crashed|closed) /.test(l)));
	const reloaded = line(/^\s*reloaded in/), fixed = line(/^v5 count=/);
	const t0 = edit((s) => s.replace('"v5 count=" +* broken', '"v5 count="'));
	await reloaded;
	times.push(performance.now() - t0);
	const n = count(await fixed);
	check(`fixed: the new build, the count kept (${count(still)} then ${n})`, n >= count(still));
	check('the reloads are not a close: helder dev runs on', dev.exitCode === null && !lines.some(closed), lines.filter(closed).join(' '));
}

// an asset's file changed: sent, nothing built, behind the same handle
async function asset() {
	check('the first build: the image', !!(await line(/^swatch: 2x2 px ff0000ff version 0 same image$/, 240000, true)));
	check('the first build: the text', !!(await line(/^note: first note$/, 10000, true)));
	for (const [w, h, c] of [[3, 1, 0x00ff00ff], [1, 4, 0x0000ffff]]) {
		await sleep(300);
		const hex = c.toString(16).padStart(8, '0');
		const sent = line(/^\s*asset swatch\.png/), swapped = line(new RegExp(`^swatch: ${w}x${h} px ${hex} version \\d+ (same|another) image$`));
		const t0 = write('swatch.png', png(w, h, c));
		await sent;
		const l = await swapped;
		times.push(performance.now() - t0);
		check(`the image ${w}x${h}: swapped in the same Image`, l.endsWith('same image'), l);
	}
	const note = line(/^note: second note$/);
	write('note.txt', 'second note\n');
	check('the text: its reader ran again', !!(await note));
	check('no build for an asset', !lines.some((l) => /^\s*rebuilt in/.test(l)), lines.filter((l) => /rebuilt/.test(l)).join(' '));
	// (a source edit still builds; the image from the file as it is now)
	const rebuilt = line(/^\s*rebuilt in/), again = line(/^swatch: 1x4 px 0000ffff version 0 same image$/);
	edit((s) => s.replace('"note: "', '"note again: "'));
	await rebuilt;
	check('a source edit: built, the image loaded as it is now', !!(await again));
	check('helder dev runs on', dev.exitCode === null && !lines.some(closed));
}

// the page told of an asset (asset-web): nothing built, the bytes served
async function assetPage() {
	const port = Number(/http:\/\/127\.0\.0\.1:(\d+)\//.exec(await line(/^\s*serving http:/, 30000, true))[1]);
	await line(/^\s*built in/, 240000, true);
	const base = `http://127.0.0.1:${port}`;
	const served = async () => Buffer.from(await (await fetch(base + '/__hxmc/assets/swatch.png')).arrayBuffer());
	check('the image served at /__hxmc/assets/', Buffer.compare(await served(), png(2, 2, 0xff0000ff)) === 0);
	check('an asset not named: 404', (await fetch(base + '/__hxmc/assets/other.png')).status === 404);
	const ws = new WebSocket(`ws://127.0.0.1:${port}/__hxmc/ws`);
	const messages = [];
	ws.onmessage = (e) => messages.push(JSON.parse(e.data));
	await new Promise((r, j) => { ws.onopen = r; ws.onerror = () => j(new Error('the WebSocket failed')); });
	const t0 = write('swatch.png', png(3, 1, 0x00ff00ff));
	for (let end = Date.now() + 30000; !messages.some((m) => m.type === 'asset') && Date.now() < end;) await sleep(5);
	times.push(performance.now() - t0);
	const m = messages.find((x) => x.type === 'asset');
	check('the page told: {"type":"asset","key":"swatch.png"}', m?.key === 'swatch.png', JSON.stringify(messages));
	check('no reload, no build', !messages.some((x) => x.type === 'reload') && !lines.some((l) => /^\s*rebuilt in/.test(l)));
	check('the new bytes served', Buffer.compare(await served(), png(3, 1, 0x00ff00ff)) === 0);
	ws.close();
}

// the program ends by itself: a crash (helder dev stays), then closed (it ends, 0)
async function exitPolicy() {
	check('a crash: shown', !!(await line(/^\s*crashed the program exited with code 3/, 240000, true)));
	await sleep(1000);
	check('a crash: helder dev stays up', dev.exitCode === null && !lines.some(closed));
	const rebuilt = line(/^\s*rebuilt in/), again = line(/^closer 1$/), close = line(/^\s*closed the program exited/);
	edit((s) => s.replace('CODE = 3', 'CODE = 0'));
	await rebuilt;
	check('a change: built and started again', !!(await again));
	await close;
	const code = await Promise.race([ended, sleep(10000).then(() => 'still running')]);
	check(`closed: helder dev ends, exit code 0 (${code})`, code === 0);
}

async function page() {
	const port = Number(/http:\/\/127\.0\.0\.1:(\d+)\//.exec(await line(/^\s*serving http:/, 30000, true))[1]);
	await line(/^\s*built in/, 240000, true);
	const base = `http://127.0.0.1:${port}`;
	const html = await (await fetch(base + '/')).text();
	const urls = [...html.matchAll(/modulepreload" href="([^"]+)"/g)].map((m) => m[1]);
	check('the page names the browser modules (ui, gfx, os, text)', ['ui', 'gfx', 'os', 'text'].every((p) => urls.some((u) => u.includes(`/${p}/`))), urls.join(' '));
	for (const u of urls) check(`${u}: served`, (await fetch(base + u)).status === 200);
	const fonts = [...html.matchAll(/"(\/__hxmc\/fonts\/[^"]+)"/g)].map((m) => m[1]);
	for (const u of fonts) check(`${u}: served`, (await fetch(base + u)).status === 200);
	const wasm = new Uint8Array(await (await fetch(base + '/__hxmc/app.wasm')).arrayBuffer());
	check('the module', wasm[0] === 0 && wasm[1] === 0x61 && wasm[2] === 0x73 && wasm[3] === 0x6d, String(wasm.slice(0, 4)));
	const ws = new WebSocket(`ws://127.0.0.1:${port}/__hxmc/ws`);
	const messages = [];
	ws.onmessage = (e) => messages.push(JSON.parse(e.data));
	await new Promise((r, j) => { ws.onopen = r; ws.onerror = () => j(new Error('the WebSocket failed')); });
	const message = async (type, from, ms = 60000) => {
		const end = Date.now() + ms;
		for (;;) {
			const m = messages.slice(from).find((x) => x.type === type);
			if (m) return m;
			if (Date.now() > end) throw new Error(`no ${type} message (${JSON.stringify(messages)})`);
			await sleep(5);
		}
	};
	for (let v = 2; v <= 4; v++) {
		await sleep(300);
		const from = messages.length;
		const t0 = edit((s) => s.replace(`>+${v - 1}<`, `>+${v}<`));
		await message('reload', from);
		times.push(performance.now() - t0);
		check(`edit ${v - 1}: a reload`, true);
	}
	const swapped = new Uint8Array(await (await fetch(base + '/__hxmc/app.wasm?swap=1')).arrayBuffer());
	check('the new module', swapped.length > 1000 && Buffer.compare(Buffer.from(swapped), Buffer.from(wasm)) !== 0);
	let from = messages.length;
	edit((s) => s.replace('>+4<', '>+5<</text> broken'));
	const error = await message('error', from);
	check('broken: the error sent (the overlay)', /Counter\.hx/.test(error.message), error.message.slice(0, 200));
	check('broken: a swap refused, the last good build kept', (await fetch(base + '/__hxmc/app.wasm?swap=2')).status === 409);
	check('broken: the module is the last good one', (await fetch(base + '/__hxmc/app.wasm')).status === 200);
	from = messages.length;
	const t0 = edit((s) => s.replace('>+5<</text> broken', '>+5<'));
	await message('ok', from);
	await message('reload', from);
	times.push(performance.now() - t0);
	check('fixed: ok, and a reload', true);
	ws.close();
}

try {
	await (mode === 'asset-web' ? assetPage() : assets ? asset() : web ? page() : exit ? exitPolicy() : native());
} catch (e) {
	console.log('FAIL ' + e.message);
	failures++;
} finally {
	dev.kill();
}
const ms = times.map((t) => Math.round(t));
if (ms.length > 0) console.log(`cli dev ${mode}: save to reload ${ms.join(', ')} ms, median ${median(ms)} ms`);
console.log(failures === 0 ? `cli dev ${mode}: ok` : `cli dev ${mode}: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
