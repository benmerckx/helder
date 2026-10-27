// `helder dev` without a window or a browser (the cli lane):
// - native: tests/cli/tally (a console program whose count helder.dev.Hot
//   keeps) copied into the work directory; edits reload it with its count
//   (on Linux in the dev host: the same process), a broken edit keeps the
//   last good build running, the fix applies;
// - web: examples/counter's Counter.hx copied there, served: the page, its
//   modules and the wasm fetched, the WebSocket (node's client) told of each
//   build (reload, error, ok), a swap after a failed build refused (409).
// The times from a save to the reload (native: the program's first frame,
// "reloaded in"; web: the reload message), each edit's, and their median.
//   node tests/cli/dev.mjs <helder> <work dir> native|web
import { spawn } from 'node:child_process';
import fs from 'node:fs';
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
const web = mode === 'web';
const file = path.join(work, 'app', web ? 'Counter.hx' : 'Tally.hx');
fs.copyFileSync(path.join(repo, web ? 'examples/counter/Counter.hx' : 'tests/cli/tally/Tally.hx'), file);
const edit = (f) => {
	const s = fs.readFileSync(file, 'utf8'), t = f(s);
	if (t === s) throw new Error('the edit changed nothing');
	fs.writeFileSync(file, t);
	return performance.now();
};

const lines = [];
const waiters = [];
const dev = spawn(path.resolve(helder), ['dev', ...(web ? ['web'] : []), path.relative(work, file), ...(web ? ['--port', '0'] : [])],
	{ cwd: work, stdio: ['ignore', 'pipe', 'pipe'] });
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
		const reloaded = line(/^helder dev: reloaded in/), next = line(new RegExp(`^v${v} count=`));
		const t0 = edit((s) => s.replace(`"v${v - 1} count="`, `"v${v} count="`));
		await reloaded;
		times.push(performance.now() - t0);
		const n = count(await next);
		check(`edit ${v - 1}: the new build, the count kept (${before} then ${n})`, n >= before && n <= before + 10);
	}
	if (hosted) check(`the dev host: the same process (${pids().length} builds)`, pids().length >= 4 && pids().every((p) => p === pids()[0]), pids().join(' '));
	const failed = line(/^helder dev: error/);
	edit((s) => s.replace('"v4 count="', '"v5 count=" +* broken'));
	await failed;
	check('broken: the error in the terminal', lines.some((l) => /Tally\.hx:\d+: characters/.test(l)));
	const still = await line(/^v4 count=/, 5000).catch(() => null);
	check('broken: the last good build keeps running', !!still && !lines.some((l) => /the program ended/.test(l)));
	const reloaded = line(/^helder dev: reloaded in/), fixed = line(/^v5 count=/);
	const t0 = edit((s) => s.replace('"v5 count=" +* broken', '"v5 count="'));
	await reloaded;
	times.push(performance.now() - t0);
	const n = count(await fixed);
	check(`fixed: the new build, the count kept (${count(still)} then ${n})`, n >= count(still));
}

async function page() {
	const port = Number(/http:\/\/127\.0\.0\.1:(\d+)\//.exec(await line(/^helder dev: http:/, 30000, true))[1]);
	await line(/^helder dev: built in/, 240000, true);
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
	await (web ? page() : native());
} catch (e) {
	console.log('FAIL ' + e.message);
	failures++;
} finally {
	dev.kill();
}
const ms = times.map((t) => Math.round(t));
console.log(`cli dev ${mode}: save to reload ${ms.join(', ')} ms, median ${median(ms)} ms`);
console.log(failures === 0 ? `cli dev ${mode}: ok` : `cli dev ${mode}: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
