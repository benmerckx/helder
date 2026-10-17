// hxmc.os.audio on WebAudio, in headless Chromium (make audio-check):
// AudioTest.wasm (AudioTest.hx) loaded by packages/os/browser.mjs with
// packages/os/imports.mjs, twice:
// - realtime: an AudioContext (Chromium without a sound card plays to a
//   fake output, at the device's pace): AudioTest checks that its callbacks
//   came at the sample rate (--rate) and reports from the callback;
// - offline: an OfflineAudioContext (browser.mjs's option audioContext),
//   which start fills at once and the harness renders: the rendered
//   samples must be AudioTest's signal (a 440 Hz sine left, 660 Hz right),
//   from the first frame, as floats (the path copies, never converts).
//   node packages/os/test/web.mjs <AudioTest.wasm>
// (Playwright from npm, with Chromium: npx playwright install chromium)
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const [wasm] = process.argv.slice(2);
if (!wasm) {
	console.error('usage: node web.mjs <AudioTest.wasm>');
	process.exit(2);
}
const RATE = 48000, FRAMES = 48000;

const files = {
	'/test.wasm': wasm,
	'/os/browser.mjs': path.join(here, '../browser.mjs'),
	'/os/imports.mjs': path.join(here, '../imports.mjs'),
};
const types = { '.mjs': 'text/javascript', '.wasm': 'application/wasm' };
const page = `<!doctype html><title>AudioTest</title>
<script type="module">
import { run } from './os/browser.mjs';
const log = [];
window.log = log;
const sample = (n, ch) => ch === 0 ? 0.5 * Math.sin(2 * Math.PI * 440 * n / ${RATE}) : 0.25 * Math.sin(2 * Math.PI * 660 * n / ${RATE});
window.realtime = async () => {
	const r = await run('test.wasm', { imports: ['os/imports.mjs'], args: ['default', '${FRAMES}', '--rate'], stdout: (s) => log.push(s), stderr: (s) => log.push('stderr: ' + s) });
	const t0 = performance.now();
	while (r.host.exitCode === null && performance.now() - t0 < 20000) await new Promise((f) => setTimeout(f, 50));
	return { exit: r.host.exitCode, log };
};
window.offline = async () => {
	let ctx;
	const audioContext = (rate, channels) => (ctx = new OfflineAudioContext(channels, ${FRAMES} + 4800, rate));
	const r = await run('test.wasm', { imports: ['os/imports.mjs'], audioContext, args: ['default', '${FRAMES}'], stdout: (s) => log.push(s), stderr: (s) => log.push('stderr: ' + s) });
	await ctx.hxmcReady;
	const b = await ctx.startRendering();
	let worst = 0, at = 0;
	for (let ch = 0; ch < 2; ch++) {
		const d = b.getChannelData(ch);
		for (let i = 0; i < ${FRAMES}; i++) {
			const e = Math.abs(d[i] - Math.fround(sample(i, ch)));
			if (e > worst) { worst = e; at = i; }
		}
	}
	return { exit: r.host.exitCode ?? r.exitCode, log, worst, at, length: b.length, channels: b.numberOfChannels, rate: b.sampleRate };
};
</script>`;
const server = createServer(async (req, res) => {
	const p = new URL(req.url, 'http://x').pathname;
	try {
		const b = p === '/' ? Buffer.from(page) : await readFile(files[p]);
		res.writeHead(200, { 'content-type': p === '/' ? 'text/html' : types[path.extname(p)] });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
}).listen(0);
const url = `http://localhost:${server.address().port}/`;

const browser = await pw.chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
console.log(`web.mjs: chromium ${browser.version()}`);
let failed = 0;
for (const mode of ['realtime', 'offline']) {
	const p = await browser.newPage();
	const errors = [];
	p.on('pageerror', (e) => errors.push(e.message));
	p.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
	await p.goto(url);
	const r = await p.evaluate((m) => window[m](), mode).catch((e) => ({ error: e.message.split('\n')[0], log: [] }));
	let ok = !r.error && errors.length === 0;
	if (mode === 'realtime') ok &&= r.exit === 0 && r.log.includes('AudioTest: passed');
	else {
		// (float32 all the way: the same values)
		ok &&= r.exit === 0 && r.channels === 2 && r.rate === RATE && r.worst === 0;
		console.log(`web.mjs: offline: rendered ${r.length} frames, ${r.channels} channels at ${r.rate} Hz; largest difference from the signal ${r.worst} (frame ${r.at})`);
	}
	if (!ok) failed++;
	console.log(`web.mjs: ${mode}${ok ? '' : ' FAILED'}${r.error ? ': ' + r.error : ''}`);
	for (const l of r.log) console.log('  ' + l);
	for (const e of errors) console.log('  error: ' + e);
	await p.close();
}
await browser.close();
server.close();
process.exit(failed ? 1 : 0);
