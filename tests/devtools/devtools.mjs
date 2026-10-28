// The devtools protocol end to end, without a window (the devtools lane):
// `helder dev` on a fixture copied into the work directory, a tool on its
// WebSocket at /__helder/devtools (node's client), and `helder inspect`.
// - console: tests/devtools/Pulse.hx: the hello, the program's log (its
//   output kept for a tool that comes late, its traces with positions),
//   frame stats (no GC bytes while it allocates nothing, bytes in every
//   frame once an edit makes it allocate), Runtime.state, a reload with the
//   tool connected (the stats on again in the new build), a build error;
// - ui: tests/devtools/Boxes.hx: Ui.getTree, before and after a reload.
//   node tests/devtools/devtools.mjs <helder> <work dir> console|ui
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
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(path.join(work, 'app'), { recursive: true });
const name = mode === 'ui' ? 'Boxes' : 'Pulse';
const file = path.join(work, 'app', name + '.hx');
fs.copyFileSync(path.join(repo, 'tests/devtools', name + '.hx'), file);
const edit = (f) => {
	const s = fs.readFileSync(file, 'utf8'), t = f(s);
	if (t === s) throw new Error('the edit changed nothing');
	fs.writeFileSync(file, t);
};

// a process's lines, and waiting for one
function lines(p) {
	const all = [], waiters = [];
	for (const s of [p.stdout, p.stderr]) {
		let buf = '';
		s.on('data', (d) => {
			buf += d;
			let nl;
			while ((nl = buf.indexOf('\n')) >= 0) {
				const l = buf.slice(0, nl);
				buf = buf.slice(nl + 1);
				all.push(l);
				if (process.env.DEV_VERBOSE) console.log('  | ' + l);
				for (const w of [...waiters]) if (w.re.test(l)) {
					waiters.splice(waiters.indexOf(w), 1);
					w.resolve(l);
				}
			}
		});
	}
	all.next = (re, ms = 120000, past = true) => {
		const l = past && all.find((x) => re.test(x));
		if (l) return Promise.resolve(l);
		return new Promise((resolve, reject) => {
			const t = setTimeout(() => reject(new Error('timed out waiting for ' + re + '; the last lines:\n' + all.slice(-20).join('\n'))), ms);
			waiters.push({ re, resolve: (x) => { clearTimeout(t); resolve(x); } });
		});
	};
	return all;
}

// a tool: requests by id, notifications kept
async function tool(port) {
	const ws = new WebSocket(`ws://127.0.0.1:${port}/__helder/devtools`);
	const notes = [], waiting = new Map();
	let id = 0;
	ws.onmessage = (e) => {
		const m = JSON.parse(e.data);
		if (m.id != null && waiting.has(m.id)) {
			waiting.get(m.id)(m);
			waiting.delete(m.id);
		} else if (m.method) notes.push(m);
	};
	await new Promise((r, j) => { ws.onopen = r; ws.onerror = () => j(new Error('the WebSocket failed')); });
	const t = {
		notes, ws,
		call: (method, params = {}) => new Promise((r, j) => {
			const n = ++id;
			const timer = setTimeout(() => j(new Error(`no answer to ${method}`)), 20000);
			waiting.set(n, (m) => { clearTimeout(timer); r(m); });
			ws.send(JSON.stringify({ jsonrpc: '2.0', id: n, method, params }));
		}),
		// the next notification (after from) for which f is true
		note: async (f, from = 0, ms = 30000) => {
			const end = Date.now() + ms;
			for (;;) {
				const m = notes.slice(from).find(f);
				if (m) return m;
				if (Date.now() > end) throw new Error('no such notification; the last: ' + JSON.stringify(notes.slice(-3)).slice(0, 500));
				await sleep(10);
			}
		},
	};
	return t;
}

const dev = spawn(path.resolve(helder), ['dev', path.relative(work, file), '--port', '0'], { cwd: work, stdio: ['ignore', 'pipe', 'pipe'] });
const out = lines(dev);
const inspects = [];

async function console_() {
	const port = Number(/devtools ws:\/\/[^:]+:(\d+)\//.exec(await out.next(/^\s*devtools ws:/, 30000))[1]);
	await out.next(/Pulse\.hx:\d+: v1 frames=/, 240000);
	const info = JSON.parse(fs.readFileSync(path.join(repo, 'bin/dev/devtools.json'), 'utf8'));
	check('bin/dev/devtools.json names the port', info.port === port && info.path === '/__helder/devtools', JSON.stringify(info));
	const t = await tool(port);
	const hello = (await t.call('Runtime.hello', { protocol: 1, client: 'devtools.mjs' })).result;
	check('hello: the protocol, the program', hello.protocol === 1 && hello.program?.name === 'Pulse' && hello.program?.target, JSON.stringify(hello));
	check('hello: another version refused', (await t.call('Runtime.hello', { protocol: 99 })).error?.code === -32010);
	const log = (await t.call('Log.enable')).result;
	check('Log.enable: the output so far, kept', log.entries.some((e) => /v1 start/.test(e.message) && e.source === 'stdout'), JSON.stringify(log.entries.slice(0, 3)));
	const traced = await t.note((m) => m.method === 'Log.entry' && m.params.source === 'trace');
	check('Log.entry: a trace with its position', /^v1 frames=\d+$/.test(traced.params.message) && /Pulse\.hx$/.test(traced.params.position?.file) && traced.params.position.line > 0
		&& traced.params.level === 'info', JSON.stringify(traced.params));
	check('a trace still in the terminal', !!(await out.next(/^.*Pulse\.hx:\d+: v1 frames=/)));

	// frame stats: nothing allocated
	const stats = async (n, from = t.notes.length) => {
		const got = [];
		const end = Date.now() + 30000;
		while (got.reduce((a, s) => a + s.params.dt.length, 0) < n) {
			if (Date.now() > end) throw new Error('too few frame stats: ' + JSON.stringify(got.at(-1)?.params).slice(0, 300));
			const m = await t.note((x) => x.method === 'Frame.stats' && !got.includes(x), from);
			got.push(m);
		}
		const col = (k) => got.flatMap((s) => s.params[k]);
		return { batches: got.length, dt: col('dt'), work: col('work'), bytes: col('gcBytes'), collections: col('gcCollections'), pauses: col('gcPauseMs'),
			agent: got.map((s) => s.params.agentBytes) };
	};
	const median = (xs) => [...xs].sort((a, b) => a - b)[xs.length >> 1];
	const enabled = (await t.call('Frame.enable', { interval: 100 })).result;
	check('Frame.enable', enabled.interval === 100, JSON.stringify(enabled));
	const quiet = await stats(120);
	check(`Frame.stats: batched (${quiet.batches} batches for ${quiet.dt.length} frames)`, quiet.batches >= 10 && quiet.batches <= quiet.dt.length / 3);
	check(`Frame.stats: frame times (median ${median(quiet.dt)} ms)`, median(quiet.dt) > 10 && median(quiet.dt) < 40);
	const zero = quiet.bytes.filter((b, i) => b === 0).length;
	check(`Frame.stats: no GC bytes while nothing allocates (${zero} of ${quiet.bytes.length} frames 0; the rest a trace's)`, zero >= quiet.bytes.length * 0.9,
		quiet.bytes.join(' '));
	check(`Frame.stats: the agent's own bytes apart (${median(quiet.agent)} a batch)`, quiet.agent.every((b) => b >= 0) && median(quiet.agent) > 0);
	const state = (await t.call('Runtime.state')).result;
	check('Runtime.state: the key Hot keeps', state.kept.some((k) => k.key === 'Pulse.main.state' || /state/.test(k.key)), JSON.stringify(state));
	const noUi = await t.call('Ui.getTree');
	check('Ui.getTree without helder.ui: no such method', noUi.error?.code === -32601, JSON.stringify(noUi));

	// a reload with the tool connected: the new build allocates
	const frameCount = (m) => Number(/frames=(\d+)/.exec(m.params.message)[1]);
	const before = frameCount(t.notes.filter((m) => m.method === 'Log.entry' && /^v1 frames=/.test(m.params.message)).at(-1));
	let from = t.notes.length;
	edit((s) => s.replace('ALLOC = 0', 'ALLOC = 100').replaceAll('"v1 ', '"v2 '));
	const reloaded = await t.note((m) => m.method === 'Runtime.reloaded', from, 60000);
	check(`Runtime.reloaded (${reloaded.params.ms} ms, build ${reloaded.params.build} ms)`, reloaded.params.ms > 0);
	check('Runtime.built and Runtime.connected', t.notes.slice(from).some((m) => m.method === 'Runtime.built') && t.notes.slice(from).some((m) => m.method === 'Runtime.connected'));
	const after = frameCount(await t.note((m) => m.method === 'Log.entry' && /^v2 frames=/.test(m.params.message), from, 30000));
	check(`the reload kept the count (${before}, then ${after})`, after > before && after < before + 600);
	from = t.notes.length;
	const busy = await stats(60, from);
	check(`Frame.stats again in the new build, GC bytes in every frame (median ${median(busy.bytes)})`, busy.bytes.every((b) => b > 0) && median(busy.bytes) >= 100 * 16,
		busy.bytes.join(' '));
	console.log(`devtools frames: idle ${median(quiet.work)} ms of work, ${median(quiet.bytes)} B; allocating ${median(busy.work)} ms, ${median(busy.bytes)} B, ` +
		`${busy.collections.reduce((a, b) => a + b, 0)} collections in ${busy.dt.length} frames (${busy.pauses.reduce((a, b) => a + b, 0).toFixed(3)} ms)`);

	// a tool that comes late sees the log so far
	const late = await tool(port);
	const kept = (await late.call('Log.enable')).result.entries;
	check(`a late tool: the log kept (${kept.length} entries)`, kept.some((e) => /^v1 frames=/.test(e.message)) && kept.some((e) => /^v2 frames=/.test(e.message)));
	late.ws.close();

	// helder inspect: the frames and the log
	const inspect = (args) => {
		const p = spawn(path.resolve(helder), ['inspect', ...args], { cwd: work, stdio: ['ignore', 'pipe', 'pipe'] });
		inspects.push(p);
		return lines(p);
	};
	const frames = inspect(['--frames']);
	check('helder inspect --frames (bin/dev/devtools.json found)', !!(await frames.next(/frames \d+-\d+: /, 30000)));
	const logs = inspect(['--log', '--port', String(port)]);
	check('helder inspect --log', !!(await logs.next(/Pulse\.hx:\d+: v2 frames=/, 30000)));

	// a broken build: the error to the tool, the program keeps running
	from = t.notes.length;
	edit((s) => s.replace('ALLOC = 100', 'ALLOC = 100 +* broken'));
	const error = await t.note((m) => m.method === 'Runtime.buildError', from, 60000);
	check('Runtime.buildError', /Pulse\.hx/.test(error.params.message), error.params.message.slice(0, 200));
	check('the build error in the log', t.notes.slice(from).some((m) => m.method === 'Log.entry' && m.params.source === 'build'));
	await t.note((m) => m.method === 'Frame.stats', t.notes.length);
	check('the last good build keeps running', true);
	check('helder inspect --log: the build error', !!(await logs.next(/Pulse\.hx:\d+: characters/, 30000)));
	t.ws.close();
}

async function ui() {
	const port = Number(/devtools ws:\/\/[^:]+:(\d+)\//.exec(await out.next(/^\s*devtools ws:/, 30000))[1]);
	await out.next(/Boxes\.hx:\d+: v1 boxes/, 240000);
	const t = await tool(port);
	await t.call('Runtime.hello', { protocol: 1 });
	// (the program's hello in: the CLI may have connected the tool first)
	const tree = async () => {
		for (let i = 0; i < 100; i++) {
			const r = await t.call('Ui.getTree');
			if (!(r.error?.code === -32001)) return r;
			await sleep(50);
		}
	};
	const r = await tree();
	const ui = r.result?.uis?.[0];
	const row = ui?.root?.children?.[0];
	check('Ui.getTree: the Ui, its root and overlay', ui?.width === 320 && ui.root.tag === 'root' && ui.overlay.tag === 'overlay', JSON.stringify(r).slice(0, 300));
	check('Ui.getTree: tags, boxes, style', row?.tag === 'row' && row.style.direction === 'row' && row.style.background === '#ff18181b' && row.children.length === 3
		&& row.children.every((b) => b.tag === 'box' && b.width === 60 && b.height === 40) && row.children[1].x === 68 && row.children[1].y === 8,
		JSON.stringify(row).slice(0, 400));
	const again = (await t.call('Ui.getTree')).result.uis[0].root.children[0];
	check('Ui.getTree: the same nodes, the same ids', again.id === row.id && again.children.map((c) => c.id).join() === row.children.map((c) => c.id).join());
	const inspect = spawn(path.resolve(helder), ['inspect', '--tree', '--port', String(port)], { cwd: work, stdio: ['ignore', 'pipe', 'pipe'] });
	inspects.push(inspect);
	const printed = lines(inspect);
	await new Promise((r) => inspect.on('exit', r));
	check('helder inspect --tree', printed.some((l) => /^ {4}box #\d+ 68,8 60x40/.test(l)), printed.join('\n'));
	const from = t.notes.length;
	edit((s) => s.replace('b.style.width = 60;', 'b.style.width = 70;').replace('"v1 boxes"', '"v2 boxes"'));
	await t.note((m) => m.method === 'Runtime.connected', from, 60000);
	const after = (await tree()).result.uis[0].root.children[0];
	check('Ui.getTree after a reload: the new build\'s', after.children.every((b) => b.width === 70) && after.children[1].x === 78, JSON.stringify(after).slice(0, 300));
	t.ws.close();
}

try {
	await (mode === 'ui' ? ui() : console_());
} catch (e) {
	console.log('FAIL ' + e.message);
	failures++;
} finally {
	for (const p of inspects) p.kill();
	dev.kill();
}
console.log(failures === 0 ? `devtools ${mode}: ok` : `devtools ${mode}: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
