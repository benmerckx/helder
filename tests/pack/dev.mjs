// `helder dev --target android` and `--target ios` without a phone (the pack
// lane): the stand-ins tests/pack/fake/adb and xcrun are the device's tools
// (each call logged), this script the app on it, speaking the dev protocol:
// - android: the first build installs the dev host's APK (install -r,
//   reverse tcp:<port>, am start); the app connects to that port; an edit
//   builds the library alone and asks for a reload with a fetch
//   ({"type":"reload","snapshot":"-","fetch":n}), the app asks for "lib <n>"
//   on a connection of its own and gets the library's bytes, the same as
//   the build's libmain.so; saved, handed over (the old connection closed,
//   a new one); then the app closed on the phone (its connection gone):
//   helder dev stays up, the next edit installs and starts it again;
// - ios: the app (an .app) installed and launched with HXMC_DEV
//   (SIMCTL_CHILD_), the app connects there; an edit builds a dylib
//   ({"type":"reload","snapshot","library"}: a Mach-O dylib on this
//   machine's disk); the app ended (simctl's launch gone) is "closed", not
//   the session's end.
//   node tests/pack/dev.mjs <helder> <work dir> android|ios
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [helder, dir, mode] = process.argv.slice(2);
const work = path.resolve(dir);
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let failures = 0;
const check = (what, ok, detail = '') => {
	console.log((ok ? 'ok   ' : 'FAIL ') + what + (ok || !detail ? '' : ': ' + detail));
	if (!ok) failures++;
};

fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(path.join(work, 'app'), { recursive: true });
const file = path.join(work, 'app', 'Hello.hx');
fs.copyFileSync(path.join(repo, 'tests/pack/Hello.hx'), file);
const log = path.join(work, 'tools.log'), envFile = path.join(work, 'app.env'), launched = path.join(work, 'launch.pid');
const tools = () => fs.existsSync(log) ? fs.readFileSync(log, 'utf8').split('\n').filter((l) => l) : [];
const edit = (from, to) => {
	const s = fs.readFileSync(file, 'utf8');
	if (!s.includes(from)) throw new Error('the edit changed nothing');
	fs.writeFileSync(file, s.replace(from, to));
};

const lines = [];
const waiters = [];
const dev = spawn(path.resolve(helder), ['dev', path.relative(work, file), '--target', mode, '--port', '0'], {
	cwd: work,
	stdio: ['ignore', 'pipe', 'pipe'],
	env: { ...process.env, ADB: path.join(repo, 'tests/pack/fake/adb'), XCRUN: path.join(repo, 'tests/pack/fake/xcrun'), FAKE_LOG: log, FAKE_ENV: envFile, FAKE_LAUNCH: launched },
});
let ended = null;
dev.on('exit', (code, signal) => (ended = code ?? signal));
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
const line = (re, ms = 180000, past = false) => {
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
async function until(f, ms, what) {
	const end = Date.now() + ms;
	while (Date.now() < end) {
		const v = f();
		if (v) return v;
		await sleep(50);
	}
	throw new Error('timed out: ' + what + '; the tools:\n' + tools().slice(-10).join('\n') + '\nthe last lines:\n' + lines.slice(-10).join('\n'));
}

// the app's connection to the dev server: its JSON lines
function connect(port) {
	return new Promise((resolve, reject) => {
		const s = net.connect(port, '127.0.0.1', () => resolve(s));
		s.on('error', reject);
		s.messages = [];
		let buf = '';
		s.on('data', (d) => {
			buf += d;
			let nl;
			while ((nl = buf.indexOf('\n')) >= 0) {
				s.messages.push(JSON.parse(buf.slice(0, nl)));
				buf = buf.slice(nl + 1);
			}
		});
	});
}
// (Android) the library asked for on a connection of its own: its bytes
function fetchLib(port, n) {
	return new Promise((resolve, reject) => {
		const s = net.connect(port, '127.0.0.1', () => s.write(`lib ${n}\n`));
		const parts = [];
		s.on('data', (d) => parts.push(d));
		s.on('end', () => resolve(Buffer.concat(parts)));
		s.on('error', reject);
	});
}

try {
	await line(/^\s*started /);
	check('the first build installed and started', true);
	let port;
	if (mode === 'android') {
		const t = tools();
		const install = t.find((l) => / install -r /.test(l)), reverse = t.find((l) => / reverse tcp:/.test(l)), start = t.find((l) => / am start /.test(l));
		check('adb install -r the APK', !!install && /bin\/dev\/android\/Hello\.apk$/.test(install), install);
		check('adb reverse tcp:<port> tcp:<port>', !!reverse && /reverse tcp:(\d+) tcp:\1$/.test(reverse), reverse);
		check('adb shell am start, the launcher\'s activity', !!start && /org\.helder\.hello\/android\.app\.NativeActivity/.test(start), start);
		check('the device the one adb lists, by its id', t.filter((l) => l.startsWith('adb -s ')).every((l) => l.startsWith('adb -s emulator-5554 ')));
		port = Number(/tcp:(\d+)/.exec(reverse)[1]);
		// (the dev host's APK asks for INTERNET; its library knows the port)
		const apk = fs.readFileSync(path.join(repo, 'bin/dev/android/Hello.apk'));
		check('the APK asks for INTERNET (its manifest)', apk.includes(Buffer.from('android.permission.INTERNET', 'utf16le')));
	} else {
		const t = tools();
		check('xcrun simctl install the .app', t.some((l) => /simctl install 8A9C6B4E-6E2B-4A43-9C7B-2C7B1E9D5F11 .*bin\/dev\/ios-sim\/Hello\.app$/.test(l)), t.join('; '));
		const launch = await until(() => tools().find((l) => / launch /.test(l)), 10000, 'simctl launch');
		check('xcrun simctl launch --console, the bundle id', /simctl launch --console --terminate-running-process 8A9C6B4E-\S+ org\.helder\.Hello$/.test(launch), launch);
		const env = await until(() => fs.existsSync(envFile) && fs.readFileSync(envFile, 'utf8'), 10000, 'the app\'s environment');
		const at = /SIMCTL_CHILD_HXMC_DEV=127\.0\.0\.1:(\d+)/.exec(env);
		check('the app\'s HXMC_DEV and HXMC_DEV_SNAPSHOT (SIMCTL_CHILD_)', !!at && /SIMCTL_CHILD_HXMC_DEV_SNAPSHOT=\S+Hello\.snapshot/.test(env), env);
		port = Number(at[1]);
		await line(/^org\.helder\.app: 4242/, 10000, true).then(() => check('simctl\'s output here', true), () => check('simctl\'s output here', false));
	}

	// the app connects; an edit swaps the next build in
	let app = await connect(port);
	await line(/^\s*connected the app on /, 10000);
	check('the app connected', true);
	edit('hello from helder on', 'hello again from helder on');
	await line(/^\s*rebuilt /);
	const reload = await until(() => app.messages.find((m) => m.type === 'reload'), 30000, 'a reload');
	if (mode === 'android') {
		check('the reload asks the app to fetch the library', reload.snapshot === '-' && typeof reload.fetch === 'string', JSON.stringify(reload));
		const got = await fetchLib(port, reload.fetch);
		const lib = fs.readFileSync(path.join(repo, 'bin/dev/android/Hello.lib/libmain.so'));
		check('"lib <n>": the build\'s library, its bytes', got.length > 1000 && got.equals(lib), got.length + ' bytes, the build\'s ' + lib.length);
		check('an ELF shared object', got.subarray(0, 4).toString('latin1') === '\x7fELF' && got.readUInt16LE(16) === 3);
		check('the library alone: no second install', tools().filter((l) => / install -r /.test(l)).length === 1);
	} else {
		check('the reload names a dylib and the snapshot', typeof reload.library === 'string' && /\.dylib$/.test(reload.library) && /Hello\.snapshot$/.test(reload.snapshot),
			JSON.stringify(reload));
		const b = fs.readFileSync(reload.library);
		check('a Mach-O dylib on this machine\'s disk (MH_DYLIB)', b.readUInt32LE(0) === 0xfeedfacf && b.readUInt32LE(12) === 6);
		check('the dylib alone: no second install', tools().filter((l) => / install /.test(l)).length === 1);
	}
	// (saved, handed over: the old build's connection closed, the new one's opened)
	app.write('{"type":"saved"}\n');
	app.end();
	app = await connect(port);
	await sleep(300);

	// the app closed on the phone: helder dev stays up, the next edit starts it again
	app.destroy();
	if (mode === 'ios') {
		// (simctl's launch ends with the app)
		process.kill(Number(fs.readFileSync(launched, 'utf8').trim()), 'SIGTERM');
		await line(/^\s*closed the app on /, 10000).then(() => check('the app ended: "closed", the session stays', true), (e) => check('the app ended: "closed"', false, e.message));
	}
	await sleep(500);
	check('helder dev is still up', ended === null, String(ended));
	edit('hello again from helder on', 'hello once more from helder on');
	await line(/^\s*started /);
	const installs = tools().filter((l) => mode === 'android' ? / install -r /.test(l) : /simctl install /.test(l)).length;
	check('no app connected: the next build installed and started it again', installs === 2, installs + ' installs');
} catch (e) {
	check(e.message, false);
}
dev.kill('SIGTERM');
await sleep(500);
if (failures > 0) console.log('--- helder dev:\n' + lines.slice(-30).join('\n') + '\n--- the tools:\n' + tools().slice(-20).join('\n'));
console.log(failures === 0 ? `pack dev ${mode}: ok` : `pack dev ${mode}: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
