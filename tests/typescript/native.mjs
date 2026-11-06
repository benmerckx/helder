import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
// helder/native's definitions (bun run test typescript-native; the
// typescript lane runs it too), each where its system is:
// - native.c: native/libc.ts (libc's and libm's functions: numbers, C
//   strings both ways, a buffer C fills, a pointer freed) on Linux,
//   natively, statically (musl) and in glibc's dynamic mode, its output
//   native/libc.out; for wasm32-wasi refused (no C library) at its line;
//   native/corefoundation.ts (Core Foundation's C API by the framework's
//   path) on a Mac;
// - native.objc: native/objc.ts (Foundation's NSProcessInfo and NSString
//   through objc_msgSend) on a Mac (CI's desktop-macos), refused for Linux;
// - native.com: native/com.ts (WIC's factory by its CLSID, a bitmap, its
//   size read back) on Windows (CI's desktop-windows), and on Linux under
//   Wine where wine and Windows' runtime objects are (HXMC_RT_DIR), refused
//   for Linux;
// - native.jni: native/jni.ts refused for Linux; on Android it is CI's
//   android job's (native/android.sh on the emulator).
const T = 'tests/typescript', N = `${T}/native`;
const dir = `bin/typescript/native-${process.pid}`;
fs.mkdirSync(dir, { recursive: true });
const built = spawnSync(process.execPath, ['src/helder/compiler/build.mjs'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] });
if (built.status !== 0) process.exit(1);
const compiler = built.stdout.trim();
function run(cmd, args, env) {
	const r = spawnSync(cmd, args, { encoding: 'utf8', timeout: 300000, env: env ? { ...process.env, ...env } : process.env });
	if (r.error) throw r.error;
	return r;
}
function ok(r, what) {
	assert.equal(r.status, 0, `${what}\n${r.stdout}\n${r.stderr}`);
}
// (a program built for this machine and run: its output)
function built_(file, name, extra = []) {
	const out = `${dir}/${name}${process.platform === 'win32' ? '.exe' : ''}`;
	ok(run(compiler, [`${N}/${file}`, ...extra, '-o', out]), `native/${file} compile ${extra.join(' ')}`);
	const r = run(out, []);
	ok(r, `native/${file} ${extra.join(' ')}`);
	return r.stdout.replace(/\r\n/g, '\n');
}
function refused(file, target, message) {
	const r = run(compiler, [`${N}/${file}`, '--target', target, '-o', `${dir}/refused`]);
	assert.notEqual(r.status, 0, `native/${file} for ${target} should be refused`);
	assert.ok(r.stderr.includes(message), `native/${file} for ${target}: ${r.stderr}`);
	console.log(`PASS native ${file} ${target} (refused)`);
}
const COM = 'true\n0\n0 7 5\n0 true\n0 true\n';
if (process.platform === 'linux') {
	const want = fs.readFileSync(`${N}/libc.out`, 'utf8');
	for (const mode of [[], ['-D', 'hxmc.libc=glibc']]) {
		assert.equal(built_('libc.ts', `libc${mode.length ? '-glibc' : ''}`, mode), want, `native/libc.ts stdout ${mode.join(' ')}`);
		console.log(`PASS native libc.ts linux-x86_64${mode.length ? ' (glibc)' : ''}`);
	}
	refused('libc.ts', 'wasm32-wasi', 'libc.ts:8: TSHX001: native.c: wasm32-wasi has no C library');
	refused('objc.ts', 'linux-x86_64', 'objc.ts:7: TSHX001: native.objc: Objective-C is Apple\'s');
	refused('com.ts', 'linux-x86_64', 'com.ts:9: TSHX001: native.com: COM is Windows\'');
	refused('jni.ts', 'linux-x86_64', 'jni.ts:8: TSHX001: native.jni: JNI is Android\'s');
	// (COM under Wine: Windows' runtime objects needed, @hxmc/win32-x64's or HXMC_RT_DIR's)
	const wine = run('sh', ['-c', 'command -v wine']).stdout.trim();
	const exe = `${dir}/com.exe`;
	const c = wine ? run(compiler, [`${N}/com.ts`, '--target', 'windows-x86_64', '-o', exe]) : null;
	if (c && c.status === 0) {
		const r = run(wine, [exe], { WINEDEBUG: '-all' });
		ok(r, 'native/com.ts under Wine');
		assert.equal(r.stdout.replace(/\r\n/g, '\n'), COM, 'native/com.ts stdout under Wine');
		console.log('PASS native com.ts windows-x86_64 (Wine)');
	} else if (c && !c.stderr.includes('no runtime object for windows-x86_64')) ok(c, 'native/com.ts compile windows-x86_64');
	else console.log(`(native/com.ts under Wine: ${wine ? 'no runtime objects for windows-x86_64' : 'no wine'}: skipped)`);
}
if (process.platform === 'darwin') {
	assert.equal(built_('corefoundation.ts', 'native-cf'), 'true 12\ntrue\n', 'native/corefoundation.ts stdout');
	console.log('PASS native corefoundation.ts');
	assert.equal(built_('objc.ts', 'native-objc'), 'true true\nnative-objc\ntrue\n12 héllo, wörld\n', 'native/objc.ts stdout');
	console.log('PASS native objc.ts');
}
if (process.platform === 'win32') {
	assert.equal(built_('com.ts', 'native-com'), COM, 'native/com.ts stdout');
	console.log('PASS native com.ts');
}
fs.rmSync(dir, { recursive: true, force: true });
