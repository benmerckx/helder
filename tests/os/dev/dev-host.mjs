// helder dev's host without a dev server (src/helder/dev; the test lane
// dev-host): the dev host (helder.dev.DevHost) and three builds of
// tests/gfx/DevHostTest.hx as its shared libraries (-D hxmc.shared
// -D hxmc.dev-host: .so, .dll, .dylib), the first run by the host with
// HXMC_DEV_NEXT naming the other two, which the running build hands over to
// in turn (helder.dev.Hot, a second after its first frame), in the same
// process, on the same window, the GPU device kept: each build's line shows
// its version, a count kept across the builds (Hot.keep, the snapshot) and
// one more, the process and the window (the HWND on Windows, the view on
// macOS, the X11 window on Linux).
//   node tests/os/dev/dev-host.mjs <compiler> <work dir> [target]
// target: this machine's (the default) or another, cross-compiled: a
// windows-x86_64 one runs under Wine (WINE, by default /usr/lib/wine/wine64;
// the caller gives the display, Xvfb), a macos-arm64 one on a Mac only (built
// here otherwise, not run). The other targets' runtime objects: their
// @hxmc/<platform> packages beside @hxmc/cli (npm i -D --force
// @hxmc/win32-x64), which the compiler finds beside its own, or HXMC_RT_DIR
// listing the packages' directories (added to the search).
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const [compilerArg, workArg, targetArg] = process.argv.slice(2);
const compiler = path.resolve(compilerArg ?? 'node_modules/.bin/haxe');
const work = path.resolve(workArg ?? fs.mkdtempSync(path.join(os.tmpdir(), 'helder-dev-host-')));
const machine = (process.platform === 'win32' ? 'windows' : process.platform === 'darwin' ? 'macos' : 'linux') + '-' + (process.arch === 'arm64' ? 'arm64' : 'x86_64');
const target = targetArg ?? machine;
const win = target.startsWith('windows-'), mac = target.startsWith('macos-');
const ext = win ? '.dll' : mac ? '.dylib' : '.so';
const wine = win && process.platform !== 'win32' ? process.env.WINE ?? '/usr/lib/wine/wine64' : null;
const runs = target === machine || wine != null;

let failures = 0;
const check = (what, ok, detail = '') => {
	console.log((ok ? 'ok   ' : 'FAIL ') + what + (ok || !detail ? '' : ': ' + detail));
	if (!ok) failures++;
};

fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(work, { recursive: true });
const std = path.join(path.dirname(compiler), 'std');
const haxe = (args) => {
	const r = spawnSync(compiler, [...args, '-D', 'hxmc.target=' + target, ...(target.startsWith('linux-') ? ['-D', 'hxmc.libc=glibc'] : []),
		...(fs.existsSync(std) ? ['-cp', std] : [])], { cwd: repo, encoding: 'utf8' });
	if (r.status !== 0) throw new Error('the build failed: ' + args.join(' ') + '\n' + (r.stdout + r.stderr).slice(-3000));
};
const host = path.join(work, 'host' + (win ? '.exe' : ''));
haxe(['-cp', 'src', '-main', 'helder.dev.DevHost', '--custom-target', 'hxmc=' + host]);
check('the host builds', fs.existsSync(host));
// (Windows: each DLL at a base of its own, as helder dev gives them)
const libs = [1, 2, 3].map((v) => {
	const lib = path.join(work, `DevHost${v}${ext}`);
	haxe(['-cp', 'src', '-cp', 'tests/gfx', ...['triangle', 'cube', 'instances', 'mips', 'formats'].flatMap((e) => ['-cp', 'examples/' + e]), '-main', 'DevHostTest', '-D', 'devhost_version=' + v, '-D', 'hxmc.dev',
		'-D', 'hxmc.shared', '-D', 'hxmc.dev-host', '-D', 'hxmc.exports=hxmc_dev_run,hxmc_dev_state',
		...(win ? ['-D', 'hxmc.dll-base=0x' + (0x10000000 + (v % 3) * 0x20000000).toString(16)] : []),
		'helder.dev.Hosted', '--custom-target', 'hxmc=' + lib]);
	return lib;
});
check(`three builds as ${ext} libraries`, libs.every((l) => fs.existsSync(l)));

if (!runs) {
	console.log(`(${target}: built, not run on ${machine})`);
} else {
	// (Wine: the loader's paths, Z: its root)
	const native = (p) => wine ? 'Z:' + p.replace(/\//g, '\\') : p;
	const out = [];
	const env = { ...process.env, HXMC_DEV_NEXT: libs.slice(1).map(native).join(';'), HXMC_DEV_SNAPSHOT: native(path.join(work, 'dev.snapshot')),
		LIBGL_ALWAYS_SOFTWARE: '1', ...(wine ? { WINEDEBUG: process.env.WINEDEBUG ?? '-all' } : {}) };
	const p = wine ? spawn(wine, [host, native(libs[0])], { env }) : spawn(host, [libs[0]], { env });
	for (const s of [p.stdout, p.stderr]) s.on('data', (d) => out.push(...d.toString().split(/\r?\n/).filter((l) => l)));
	const ended = new Promise((r) => p.on('exit', r));
	const t0 = Date.now();
	while (Date.now() - t0 < 120000 && !out.some((l) => /^DevHostTest: v3 /.test(l)) && p.exitCode == null)
		await new Promise((r) => setTimeout(r, 250));
	p.kill();
	await Promise.race([ended, new Promise((r) => setTimeout(r, 3000))]);
	if (wine) spawnSync(path.join(path.dirname(wine), 'wineserver'), ['-k']);
	for (const l of out) console.log('  | ' + l);
	const at = (v) => out.find((l) => l.startsWith(`DevHostTest: v${v} `)) ?? '';
	const field = (l, k) => new RegExp(`${k}=(\\S+)`).exec(l)?.[1];
	check('two builds swapped in', !!at(3));
	check('the count kept across the builds (n=1, 2, 3)', [1, 2, 3].every((v) => field(at(v), 'n') === String(v)), [1, 2, 3].map(at).join(' / '));
	const pid = field(at(1), 'pid');
	check(`the same process (${pid})`, !!pid && [2, 3].every((v) => field(at(v), 'pid') === pid));
	const view = field(at(1), 'view');
	check(`the same window (${view})`, !!view && view !== '0' && [2, 3].every((v) => field(at(v), 'view') === view));
}
console.log(failures === 0 ? `dev-host (${target}): ok` : `dev-host (${target}): ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
