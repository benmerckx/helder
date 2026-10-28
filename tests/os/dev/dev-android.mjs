// The dev loop on Android (CI's android job, on its emulator; not run
// elsewhere): `helder dev --target android` on a small program drawing
// helder.gfx's cube, built for the device adb reaches (its ABI: x86_64 on
// the emulator), its count (Hot.keep) printed (logcat, tag hxmc), set to 3
// on a cold start:
// - the APK installed and started once (the dev host: its activity glue
//   keeps the window, the EGL context and the input queue);
// - two edits: each build's library fetched by the running build into the
//   app's files and loaded into the same process (the same pid, as adb
//   sees it), the count kept, the new code running; no crash;
// - the swaps' times, from the change seen to the new build's first frame.
//   node tests/os/dev/dev-android.mjs <helder> [work dir]
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../..');
const helder = path.resolve(process.argv[2] ?? 'bin/cli/helder');
const work = path.resolve(process.argv[3] ?? fs.mkdtempSync(path.join(os.tmpdir(), 'helder-dev-android-')));
const PKG = 'org.helder.counter';
const ADB = process.env.ADB ?? 'adb';

let failures = 0;
const check = (what, ok, detail = '') => {
	console.log((ok ? 'ok   ' : 'FAIL ') + what + (ok || !detail ? '' : ': ' + detail));
	if (!ok) failures++;
};
const adb = (...args) => spawnSync(ADB, args, { encoding: 'utf8' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(path.join(work, 'app'), { recursive: true });
const counter = path.join(work, 'app', 'Counter.hx');
// (a drawn program without fonts: ui's need a font file on Android; the
// cube of helder.gfx's examples, the count in Hot.keep)
const v1 = `import helder.dev.Hot;
import helder.gfx.*;
import helder.os.*;

class Counter {
	static var BUILD = Std.int((Sys.time() * 1000) % 1000000000);

	static function main() {
		var state = Hot.keep("state", () -> {count: 0});
		if (!Hot.reloading) state.count = 3;
		var w = new Window("Counter", 320, 480);
		var device = Device.create(w.surface);
		var cube = new Cube(device);
		var frames = 0;
		App.run(() -> {
			var enc = device.beginFrame();
			if (enc == null) return;
			cube.draw(enc, frames * 0.02);
			device.endFrame();
			if (++frames == 5) trace("v1 count=" + state.count + " build=" + BUILD);
		}, e -> {});
	}
}
`;
fs.writeFileSync(counter, v1);
// (the cube's class beside it: helder dev's entry is the file, its class path the directory)
fs.copyFileSync(path.join(repo, 'examples/cube/Cube.hx'), path.join(work, 'app', 'Cube.hx'));
const edit = (f) => fs.writeFileSync(counter, f(fs.readFileSync(counter, 'utf8')));

adb('wait-for-device');
adb('logcat', '-c');
const lines = [];
const waiters = [];
const dev = spawn(helder, ['dev', 'app/Counter.hx', '--target', 'android', '--port', '0'],
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
// (the next line matching re from now on; with past, one already printed too)
const line = (re, ms = 300000, past = false) => {
	const l = past ? lines.find((x) => re.test(x)) : null;
	if (l) return Promise.resolve(l);
	const pr = new Promise((resolve, reject) => {
		const t = setTimeout(() => reject(new Error('timed out waiting for ' + re + '; the last lines:\n' + lines.slice(-30).join('\n'))), ms);
		waiters.push({ re, resolve: (x) => { clearTimeout(t); resolve(x); } });
	});
	pr.catch(() => {});
	return pr;
};
// logcat's hxmc lines (what the program prints), and a crash
const logcat = () => adb('logcat', '-d', '-s', 'hxmc:*', 'helder.os:*', 'AndroidRuntime:E', 'DEBUG:*', 'libc:*').stdout ?? '';
const crashed = () => /Fatal signal|FATAL EXCEPTION|dlopen failed|CANNOT LINK/.test(adb('logcat', '-d').stdout ?? '');
async function printed(re, what, ms = 120000) {
	const end = Date.now() + ms;
	while (Date.now() < end) {
		const m = logcat().split('\n').find((l) => re.test(l));
		if (m) return m;
		if (crashed()) {
			console.log((adb('logcat', '-d').stdout ?? '').split('\n').filter((l) => /hxmc|Fatal|FATAL|DEBUG|dlopen|LINK|backtrace|#\d\d pc/.test(l)).slice(-80).join('\n'));
			throw new Error(what + ': the app crashed');
		}
		await sleep(500);
	}
	throw new Error(what + `: no ${re} in logcat:\n` + logcat().split('\n').slice(-30).join('\n'));
}
const pidOf = () => (adb('shell', 'pidof', PKG).stdout ?? '').trim();

const times = [];
try {
	await line(/^\s*started org\.helder\.counter on /, 600000, true);
	const first = await printed(/v1 count=3 build=/, 'the first build');
	check('the APK installed, the first build runs, its state changed', !!first);
	await sleep(2000);
	const pid = pidOf();
	check('the app has a process', pid !== '', pid);
	await line(/^\s*connected the app on /, 30000, true).catch(() => check('the app connected to the dev server', false));

	const swapped = line(/^\s*reloaded in/);
	edit((s) => s.replace('frames * 0.02', 'frames * 0.03').replace('"v1 count="', '"v2 count="'));
	times.push(await swapped);
	const v2 = await printed(/v2 count=\S+ build=/, 'edited');
	check('edited: the new build, the count kept', /v2 count=3 /.test(v2), v2);
	check('edited: the same process', pidOf() === pid, pidOf() + ' was ' + pid);

	const swapped2 = line(/^\s*reloaded in/);
	edit((s) => s.replace('"v2 count="', '"v3 count="'));
	times.push(await swapped2);
	const v3 = await printed(/v3 count=\S+ build=/, 'edited again');
	check('edited again: the new build, the count kept', /v3 count=3 /.test(v3), v3);
	check('edited again: the same process', pidOf() === pid, pidOf() + ' was ' + pid);
	check('no crash', !crashed());
} catch (e) {
	console.log('FAIL ' + e.message);
	failures++;
} finally {
	dev.kill();
	const all = adb('logcat', '-d').stdout ?? '';
	if (process.env.DEV_ANDROID_LOG) fs.writeFileSync(process.env.DEV_ANDROID_LOG, all);
	// (what the app and the system said about it, in the job's log)
	if (failures > 0) {
		console.log('--- the dev server:\n' + lines.slice(-40).join('\n'));
		console.log('--- logcat (the app, its crash, the activity manager):');
		console.log(all.split('\n').filter((l) => /hxmc|devtest|Fatal|FATAL|DEBUG|AndroidRuntime|dlopen|LINK|backtrace|#\d\d pc|libc|linker|avc:/.test(l)).slice(-200).join('\n'));
		console.log('--- ps: ' + (adb('shell', 'ps', '-A').stdout ?? '').split('\n').filter((l) => /devtest/.test(l)).join('\n'));
	}
}
for (const t of times) console.log('  ' + t);
console.log(failures === 0 ? 'dev-android: ok' : `dev-android: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
