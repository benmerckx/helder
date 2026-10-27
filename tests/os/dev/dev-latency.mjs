// The dev loop's times (docs/dev.md, "Times"): `hxmc dev` on a copy of one of
// helder.ui's examples, a one-line edit of its main (a string) saved again
// and again, each reload's time from the change seen to the new build's
// first frame and its build's, then the medians. In headless Chromium
// (web) or natively (native: under Xvfb on Linux, from the
// caller, as `xvfb-run node ...`).
//   node tests/os/dev/dev-latency.mjs <compiler> <Counter|Todo|...> [web|native] [edits]
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../../..');
const [compilerArg, example = 'Counter', mode = 'web', editsArg = '6'] = process.argv.slice(2);
// (its directory: examples/native-form for NativeForm)
const exampleDir = example.replace(/[A-Z]/g, (c, i) => (i ? '-' : '') + c.toLowerCase());
const compiler = path.resolve(compilerArg ?? 'node_modules/.bin/haxe');
const edits = Number(editsArg);
const web = mode === 'web';
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'hxmc-dev-latency-'));
fs.mkdirSync(path.join(work, 'app'));
const src = path.join(work, 'app', example + '.hx');
const original = fs.readFileSync(path.join(repo, 'examples', exampleDir, example + '.hx'), 'utf8');
const marked = original.replace('static function main() {', 'static function main() {\n\t\tvar edit = "edit 0";\n\t\ttrace(edit);');
if (marked === original) throw new Error(example + ': no main');
fs.writeFileSync(src, marked);
const cp = [`-cp ${path.join(repo, 'src')}`];
// (the examples' class path for the files they use; the copy last, which wins)
fs.writeFileSync(path.join(work, 'build.hxml'), [...cp, `-cp ${path.join(repo, 'examples', exampleDir)}`, '-cp app',
	'-D helder.view.renderer.ui=helder.ui.view.NodeRenderer', `-main ${example}`,
	...(web ? ['-D hxmc.target=wasm32-wasi', `--custom-target hxmc=out/app.wasm`]
		: [...(process.platform === 'linux' ? ['-D hxmc.libc=glibc'] : []), '--custom-target hxmc=out/app'])].join('\n') + '\n');

const port = await new Promise((r) => {
	const s = net.createServer().listen(0, () => {
		const p = s.address().port;
		s.close(() => r(p));
	});
});
const waiters = [];
const dev = spawn(process.execPath, [path.join(repo, 'node_modules/@hxmc/cli/hxmc/bootstrap/dev.mjs'), compiler, '--port', String(port), 'build.hxml'],
	{ cwd: work, stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, LIBGL_ALWAYS_SOFTWARE: '1' } });
for (const s of [dev.stdout, dev.stderr]) {
	let buf = '';
	s.on('data', (d) => {
		buf += d;
		let nl;
		while ((nl = buf.indexOf('\n')) >= 0) {
			const l = buf.slice(0, nl);
			buf = buf.slice(nl + 1);
			for (const w of [...waiters]) if (w.re.test(l)) {
				waiters.splice(waiters.indexOf(w), 1);
				w.resolve(l);
			}
		}
	});
}
const line = (re) => new Promise((resolve) => waiters.push({ re, resolve }));

let browser = null;
const results = [];
try {
	if (web) {
		let pw;
		try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
		await line(/^hxmc dev: built in/);
		browser = await pw.chromium.launch({ args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'] });
		const page = await browser.newPage();
		await page.goto(`http://localhost:${port}/`);
		await page.waitForFunction(() => window.hxmcDev?.frames > 0, null, { timeout: 120000 });
	} else await line(/edit 0/);
	await new Promise((r) => setTimeout(r, 1000));
	for (let i = 1; i <= edits; i++) {
		const done = line(/^hxmc dev: (?:swapped|reloaded) in/);
		fs.writeFileSync(src, fs.readFileSync(src, 'utf8').replace(`"edit ${i - 1}"`, `"edit ${i}"`));
		const l = await done;
		const m = /(?:swapped|reloaded) in (\d+) ms \(build (\d+) ms\)/.exec(l);
		results.push({ total: Number(m[1]), build: Number(m[2]) });
		console.log(`${example} ${mode} edit ${i}: ${m[1]} ms (build ${m[2]} ms)`);
		await new Promise((r) => setTimeout(r, 500));
	}
} finally {
	if (browser) await browser.close();
	dev.kill();
}
const median = (xs) => xs.slice().sort((a, b) => a - b)[xs.length >> 1];
console.log(`${example} ${mode}: median ${median(results.map((r) => r.total))} ms save to frame, build ${median(results.map((r) => r.build))} ms (${results.length} edits)`);
fs.rmSync(work, { recursive: true, force: true });
