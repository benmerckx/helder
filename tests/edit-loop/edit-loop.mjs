// The edit loop's times (the edit-loop lane): `helder dev` kept warm on a
// copy of examples/todo (Haxe) and examples/ts-todo (TSX), in a window
// (Linux: under Xvfb when there is no display), edited as the studio will
// edit them, each edit timed from the file saved to the reloaded build's
// first frame (Runtime.ready on the devtools' WebSocket), and split by where
// the time went (HELDER_DEV_PHASES=1: Runtime.built's phases, the
// compiler's and hxmc's; Runtime.ready's startedAt and ms):
//
//   watcher     the save to the change seen (helder.async's SampledWatcher)
//   patch       live literals: the change seen to the values set in the program (compared, sent, flushed)
//   check       tsgo's check (TypeScript)
//   typing      Haxe's init macros and typing, its macros (markup) included
//   filters     Haxe's filters (DCE, the analyzer), to generation
//   lowering    hxmc's IR (and the TypeScript program's)
//   codegen     hxmc's code generation (prepare, codegen, data)
//   link        hxmc's own linker
//   server      the server's request beyond the phases (its arguments, the target's init, the module cache's checks and writes)
//   cli         helder dev's build beyond the request (the assets' step, the tables of live literals read)
//   reload      the build done to the new build started (snapshot, dispose, the library loaded)
//   frame       the new build's start to its first frame; live literals': the patch to its frame
//   other       the rest: the relays (the program to helder dev to the tool)
//
// Three kinds of edit, each EDITS times (median, and the range):
//   literal     a colour in the markup (the title's): live literals' path,
//               patched with no build (EDIT_LOOP_ARGS=--no-literals: built)
//   body        a component's body changed (a handler's code)
//   component   a component added, and used
//
//   node tests/edit-loop/edit-loop.mjs <helder> <work dir> [todo|ts-todo ...]
// Writes <work dir>/results.md and results.json.
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [helder, work, ...only] = process.argv.slice(2);
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const EDITS = Number(process.env.EDITS ?? 5);
const WARMUP = Number(process.env.WARMUP ?? 2);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const median = (xs) => xs.length === 0 ? NaN : [...xs].sort((a, b) => a - b)[xs.length >> 1];

// (one form of a body to the other, whichever it has)
const swap = (s, a, b) => s.includes(a) ? s.replace(a, b) : s.replace(b, a);

const apps = {
	todo: {
		entry: 'Todo.hx', files: ['examples/todo/Todo.hx'], file: 'Todo.hx',
		literal: (s, i) => s.replace(/color="#[0-9a-f]{6}">todos/, `color="${i % 2 ? '#ef4444' : '#3b82f6'}">todos`),
		body: (s) => swap(s, 'var toggle = () -> props.checked(c -> !c);', 'var toggle = () -> {\n\t\t\tprops.checked(c -> !c);\n\t\t};'),
		component: (s, i) => s.replace('\tpublic function view():View {', `\tstatic function Badge${i}(props:{label:String}):View\n\t\treturn <text color="#71717a" font-size={12}>{props.label}</text>;\n\n\tpublic function view():View {`)
			.replace('color="#3b82f6">todos</text>', `color="#3b82f6">todos</text>\n\t\t\t<Badge${i} label="badge ${i}"/>`).replace(/color="#ef4444">todos<\/text>/, `color="#ef4444">todos</text>\n\t\t\t<Badge${i} label="badge ${i}"/>`),
	},
	'ts-todo': {
		entry: '.', files: ['examples/ts-todo/app.tsx', 'examples/ts-todo/main.tsx', 'examples/ts-todo/todos.ts'], file: 'app.tsx',
		literal: (s, i) => s.replace(/color="#[0-9a-f]{6}">todos/, `color="${i % 2 ? '#ef4444' : '#3b82f6'}">todos`),
		body: (s) => swap(s, 'onPress={() => props.onClick()}', 'onPress={() => { props.onClick(); }}'),
		component: (s, i) => s.replace('const remaining = memo(', `function Badge${i}(props: { label: string }) {\n\treturn <text color="#71717a" font-size={12}>{props.label}</text>;\n}\n\nconst remaining = memo(`)
			.replace(/(color="#[0-9a-f]{6}">todos<\/text>)/, `$1\n\t\t<Badge${i} label="badge ${i}"/>`),
	},
};

// (a display: the one there is, else a virtual one, Xvfb)
let xvfb = null;
const env = { ...process.env, HELDER_DEV_PHASES: '1' };
if (process.platform === 'linux' && !env.DISPLAY) {
	const n = 90 + (process.pid % 9);
	xvfb = spawn('Xvfb', [`:${n}`, '-screen', '0', '1280x1024x24', '-nolisten', 'tcp'], { stdio: 'ignore' });
	env.DISPLAY = `:${n}`;
	await sleep(500);
}

async function lane(name) {
	const app = apps[name];
	const dir = path.join(work, name);
	fs.rmSync(dir, { recursive: true, force: true });
	fs.mkdirSync(dir, { recursive: true });
	for (const f of app.files) fs.copyFileSync(path.join(repo, f), path.join(dir, path.basename(f)));
	const file = path.join(dir, app.file);
	const lines = [];
	const port = 4500 + Math.floor(Math.random() * 400);
	const dev = spawn(path.resolve(helder), ['dev', app.entry, '--port', String(port), ...(process.env.EDIT_LOOP_ARGS ? process.env.EDIT_LOOP_ARGS.split(' ') : [])],
		{ cwd: dir, stdio: ['ignore', 'pipe', 'pipe'], env });
	// (helder dev ended with the lane, whatever happens)
	process.on('exit', () => { try { dev.kill('SIGTERM'); } catch {} });
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
			}
		});
	}
	// (the devtools' WebSocket: the line helder dev prints names it)
	let url = null;
	for (let i = 0; i < 600 && !url; i++) {
		url = lines.map((l) => /(ws:\/\/\S+\/__helder\/devtools)/.exec(l)?.[1]).find((u) => u);
		if (!url) await sleep(100);
	}
	if (!url) throw new Error(`${name}: helder dev named no devtools WebSocket:\n` + lines.join('\n'));
	const ws = new WebSocket(url);
	await new Promise((r, j) => { ws.onopen = r; ws.onerror = () => j(new Error('the devtools WebSocket failed')); });
	const events = [];
	const waiters = [];
	let nextId = 1;
	const pending = new Map();
	ws.onmessage = (m) => {
		const msg = JSON.parse(m.data);
		if (msg.id != null && pending.has(msg.id)) {
			pending.get(msg.id)(msg);
			pending.delete(msg.id);
			return;
		}
		if (!msg.method) return;
		const ev = { method: msg.method, params: msg.params, at: Date.now() };
		events.push(ev);
		for (const w of [...waiters]) if (w.test(ev)) { waiters.splice(waiters.indexOf(w), 1); w.resolve(ev); }
	};
	const rpc = (method, params = {}) => new Promise((r) => { const id = nextId++; pending.set(id, r); ws.send(JSON.stringify({ jsonrpc: '2.0', id, method, params })); });
	const next = (test, ms = 180000) => new Promise((resolve, reject) => {
		const t = setTimeout(() => reject(new Error(`${name}: timed out; the last lines:\n` + lines.slice(-25).join('\n'))), ms);
		waiters.push({ test, resolve: (x) => { clearTimeout(t); resolve(x); } });
	});
	await rpc('Runtime.hello', { protocol: 1, client: 'edit-loop' });
	await next((e) => e.method === 'Runtime.ready', 300000);
	const rows = {};
	const save = (f, i) => {
		const s = fs.readFileSync(file, 'utf8'), t = f(s, i);
		if (t === s) throw new Error(`${name}: an edit changed nothing`);
		fs.writeFileSync(file + '.tmp', t);
		const at = Date.now();
		fs.renameSync(file + '.tmp', file);
		return at;
	};
	let edit = 0;
	for (const kind of ['literal', 'body', 'component']) {
		rows[kind] = [];
		for (let i = 0; i < WARMUP + EDITS; i++) {
			await sleep(400);
			edit++;
			const built = next((e) => e.method === 'Runtime.built' || e.method === 'Runtime.buildError' || e.method === 'Runtime.patched');
			const t0 = save(app[kind], edit);
			const b = await built;
			if (b.method === 'Runtime.buildError') throw new Error(`${name}: ${kind}: the build failed:\n${b.params.message}`);
			if (b.method === 'Runtime.patched') {
				// (live literals: no build; the frame after the values were set)
				if (i >= WARMUP) {
					const r = { path: 'literals', total: b.at - t0, watcher: b.params.changedAt * 1000 - t0, frame: b.params.frameMs };
					r.patch = r.total - r.watcher - r.frame;
					rows[kind].push(r);
				}
				continue;
			}
			const ready = await next((e) => e.method === 'Runtime.ready');
			if (i < WARMUP) continue;
			const ph = b.params.phases ?? { phases: [] };
			const of = (n) => ph.phases.filter((x) => x.name === n).reduce((a, x) => a + x.ms, 0);
			const h = ph.hxmc ?? {};
			const gen = of('codegen and link');
			const link = h.link ?? NaN, codegen = (h.prepare ?? 0) + (h.codegen ?? 0) + (h.data ?? 0) + (h.runtime ?? 0);
			rows[kind].push({
				path: 'build',
				total: ready.at - t0,
				watcher: ph.changedAt * 1000 - t0,
				check: of('check (tsgo)'),
				typing: of('init macros') + of('typing'),
				filters: of('filters') + of('to generation'),
				lowering: of('lowering') + of('lowering (TypeScript)'),
				codegen: Number.isNaN(link) ? gen : gen - link,
				link,
				server: ph.requestMs - (ph.ms ?? 0),
				cli: b.params.ms - ph.requestMs,
				build: b.params.ms,
				reload: ready.params.startedAt != null ? ready.params.startedAt * 1000 - ph.endedAt * 1000 : NaN,
				frame: ready.params.ms ?? NaN,
				modules: h.modules, compiled: h.compiled,
			});
			const r = rows[kind].at(-1);
			r.other = r.total - ['watcher', 'check', 'typing', 'filters', 'lowering', 'codegen', 'link', 'server', 'cli', 'reload', 'frame'].reduce((a, c) => a + (Number.isNaN(r[c]) ? 0 : r[c]), 0);
		}
	}
	ws.close();
	dev.kill('SIGTERM');
	await new Promise((r) => { dev.on('exit', r); setTimeout(r, 5000); });
	return rows;
}

const results = {};
try {
	for (const name of only.length > 0 ? only : Object.keys(apps)) results[name] = await lane(name);
} finally {
	if (xvfb) xvfb.kill();
}
const cols = ['total', 'watcher', 'patch', 'check', 'typing', 'filters', 'lowering', 'codegen', 'link', 'server', 'cli', 'reload', 'frame', 'other'];
const fmt = (v) => v == null || Number.isNaN(v) ? '' : String(Math.round(v));
let md = `# The edit loop (\`bun run test edit-loop\`)\n\nms, median of ${EDITS} edits after ${WARMUP} unmeasured (from the save to the new frame).\n\n`;
md += '| app | edit | path | ' + cols.join(' | ') + ' | modules compiled |\n|' + ' --- |'.repeat(cols.length + 4) + '\n';
for (const [name, rows] of Object.entries(results))
	for (const [kind, rs] of Object.entries(rows)) {
		const path = rs.length > 0 ? rs[0].path : '';
		md += `| ${name} | ${kind} | ${path} | ` + cols.map((c) => fmt(median(rs.map((r) => r[c]).filter((v) => v != null && !Number.isNaN(v))))).join(' | ')
			+ ` | ${rs.length > 0 && rs[0].compiled != null ? median(rs.map((r) => r.compiled)) + ' of ' + rs[0].modules : ''} |\n`;
	}
fs.mkdirSync(work, { recursive: true });
fs.writeFileSync(path.join(work, 'results.md'), md);
fs.writeFileSync(path.join(work, 'results.json'), JSON.stringify(results, null, 1));
console.log(md);
