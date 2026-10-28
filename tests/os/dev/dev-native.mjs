// The dev loop natively (npm test -- dev; docs/dev.md): `hxmc dev` on a copy
// of helder.ui's Counter example as a native program in a window (run under
// Xvfb on Linux), its count printed, set to 3 on a cold start (as a click
// would; a reload must bring it back, not set it again):
// - an edit: the new build swapped in, the count still 3; on Linux (the dev
//   host: each build a shared library loaded into the same process) the
//   process and the window are the same (the window's id and the process
//   the host's builds print), the build is new (its start stamp);
// - the signal's type changed: reset, logged;
// - a compile error: the program keeps running (the same process), the
//   error in the terminal; fixed: the new build, the count kept;
// - the reloads' times, from the change seen to the new build's first frame.
//   node tests/os/dev/dev-native.mjs <compiler> [work dir] [--helder=<exe>]
// (--helder: `helder dev app/Counter.hx` instead of dev.mjs, its build not
// compared with a fresh one)
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../../..');
const helder = process.argv.find((a) => a.startsWith('--helder='))?.slice(9);
const positional = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const compiler = path.resolve(positional[0] ?? 'node_modules/.bin/haxe');
const work = path.resolve(positional[1] ?? fs.mkdtempSync(path.join(os.tmpdir(), 'hxmc-dev-native-')));

let failures = 0;
const check = (what, ok, detail = '') => {
	console.log((ok ? 'ok   ' : 'FAIL ') + what + (ok || !detail ? '' : ': ' + detail));
	if (!ok) failures++;
};

fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(path.join(work, 'app'), { recursive: true });
const counter = path.join(work, 'app', 'Counter.hx');
const original = fs.readFileSync(path.join(repo, 'examples/counter/Counter.hx'), 'utf8');
const v1 = original.replace('var count = signal(0);',
	'var count = signal(0);\n\t\tif (!helder.dev.Hot.reloading) count.value = 3;\n\t\teffect(() -> trace("v1 count=" + count.value + " pid=" + PID));')
	.replace('static function main() {', 'static var PID = Std.int((Sys.time() * 1000) % 1000000000);\n\n\tstatic function main() {');
if (v1 === original) throw new Error('Counter.hx changed: its signal line is not found');
fs.writeFileSync(counter, v1);
const cp = [`-cp ${path.join(repo, 'src')}`];
const glibc = process.platform === 'linux' ? ['-D hxmc.libc=glibc'] : [];
fs.writeFileSync(path.join(work, 'build.hxml'), ['-cp app', ...cp, '-main Counter', ...glibc,
	`--custom-target hxmc=out/counter${process.platform === 'win32' ? '.exe' : ''}`].join('\n') + '\n');
const edit = (f) => fs.writeFileSync(counter, f(fs.readFileSync(counter, 'utf8')));

const lines = [];
const waiters = [];
const dev = helder ? spawn(path.resolve(helder), ['dev', 'app/Counter.hx'], { cwd: work, stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, LIBGL_ALWAYS_SOFTWARE: '1' } })
	: spawn(process.execPath, [path.join(repo, 'node_modules/@hxmc/cli/hxmc/bootstrap/dev.mjs'), compiler, 'build.hxml'],
		{ cwd: work, stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, LIBGL_ALWAYS_SOFTWARE: '1' } });
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
// the next line matching re, from now on (or one already printed, with past)
const line = (re, ms = 120000, past = false) => {
	if (past) {
		const l = lines.find((x) => re.test(x));
		if (l) return Promise.resolve(l);
	}
	const pr = new Promise((resolve, reject) => {
		const t = setTimeout(() => reject(new Error('timed out waiting for ' + re + '; the last lines:\n' + lines.slice(-30).join('\n'))), ms);
		waiters.push({ re, resolve: (l) => { clearTimeout(t); resolve(l); } });
	});
	// (handled when awaited; one not awaited yet must not end the run)
	pr.catch(() => {});
	return pr;
};
const pidOf = (l) => /pid=(\d+)/.exec(l)?.[1];
// the dev host's window and process, as each build that takes it prints it
// (Linux, Windows; on macOS the builds run in the host too, but print nothing of it)
const hosted = process.platform === 'linux' || process.platform === 'win32';
const hostWindows = () => lines.filter((l) => /^helder\.dev: the host's window /.test(l));
const sameHost = (what) => {
	if (!hosted) return;
	const w = hostWindows();
	check(`${what}: the same process and window (${w.length} builds)`, w.length >= 2 && w.every((l) => l === w[0]), JSON.stringify(w));
};

const times = [];
try {
	const first = await line(/v1 count=3 pid=/, 240000, true);
	check('the first build runs, its state changed', !!first);

	const reloaded = line(/^(?:(?:hxmc|helder) dev: |\s*)(?:swapped|reloaded) in/);
	const v2 = line(/v2 count=\S+ pid=/);
	edit((s) => s.replace('label="+1"', 'label="+2"').replace('>+1<', '>+2<').replace('"v1 count="', '"v2 count="'));
	times.push(await reloaded);
	const v2l = await v2;
	check('edited: the new build, the count kept', /v2 count=3 /.test(v2l) && pidOf(v2l) !== pidOf(first), v2l);
	await new Promise((r) => setTimeout(r, 200));
	sameHost('edited');

	const reloaded2 = line(/^(?:(?:hxmc|helder) dev: |\s*)(?:swapped|reloaded) in/);
	const reset = line(/Counter\.main\.count reset: its type changed/);
	const v3 = line(/v3 count=\S+ pid=/);
	edit((s) => s.replace('signal(0)', 'signal(0.5)').replace('count.value = 3;', 'count.value = 3.5;').replace('"v2 count="', '"v3 count="'));
	times.push(await reloaded2);
	check('type changed: logged', !!(await reset.catch(() => null)));
	const v3l = await v3;
	check('type changed: reset', /v3 count=0\.5 /.test(v3l), v3l);

	const failed = line(/^(?:(?:hxmc|helder) dev: error|\s*failed in)/);
	edit((s) => s.replace('"v3 count="', '"v4 count=" +* broken'));
	await failed;
	check('error: in the terminal', lines.some((l) => /Counter\.hx:\d+: characters/.test(l)));
	await new Promise((r) => setTimeout(r, 1000));
	check('error: the program keeps running', !lines.some((l) => /the program ended|^\s*(?:crashed|closed) /.test(l)));

	const reloaded3 = line(/^(?:(?:hxmc|helder) dev: |\s*)(?:swapped|reloaded) in/);
	const v5 = line(/v5 count=\S+ pid=/);
	edit((s) => s.replace('"v4 count=" +* broken', '"v5 count="'));
	times.push(await reloaded3);
	const v5l = await v5;
	check('fixed: the new build, the count kept', /v5 count=0\.5 /.test(v5l) && pidOf(v5l) !== pidOf(v3l), v5l);
	await new Promise((r) => setTimeout(r, 200));
	sameHost('fixed');
	if (hosted) check('no program ended or restarted', !lines.some((l) => /the program ended|^\s*(?:crashed|closed) /.test(l)));
} catch (e) {
	console.log('FAIL ' + e.message);
	failures++;
} finally {
	dev.kill();
}
// the dev server's last build (its compilation server reusing typed modules,
// lowered bodies and objects across the edits) is what a fresh build makes
// (the dev host's: the last library, against one built with its options)
const devOut = path.join(work, 'out/counter');
const libs = fs.existsSync(devOut + '.dev') ? fs.readdirSync(devOut + '.dev').filter((f) => f.endsWith('.so')).sort((a, b) => parseInt(b) - parseInt(a)) : [];
const last = hosted && libs.length ? path.join(devOut + '.dev', libs[0]) : devOut;
if (failures === 0 && !helder && fs.existsSync(last)) {
	const kept = fs.readFileSync(last);
	const std = path.join(path.dirname(compiler), 'std');
	const r = spawnSync(compiler, ['-D', 'hxmc.dev', ...(last !== devOut ? ['-D', 'hxmc.shared', '-D', 'hxmc.dev-host', '-D', 'hxmc.exports=hxmc_dev_run,hxmc_dev_state'] : []),
		'build.hxml', ...(fs.existsSync(std) ? ['-cp', std] : [])],
		{ cwd: work, encoding: 'utf8', env: { ...process.env, HXMC_MODULE_CACHE: '0' } });
	check('the last build is a fresh build, byte for byte', r.status === 0 && Buffer.compare(kept, fs.readFileSync(devOut)) === 0, (r.stderr ?? '').slice(-800));
}
for (const t of times) console.log('  ' + t);
console.log(failures === 0 ? 'dev-native: ok' : `dev-native: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
