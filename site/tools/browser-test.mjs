// The playground's compiler in real browsers (Playwright: chromium, firefox,
// webkit): serves a built site (`make site`), starts its worker as the page
// does and runs a program with --interp, compiles it to HXB, and asks for
// diagnostics and a completion.
//   node site/tools/browser-test.mjs bin/site [chromium firefox webkit]
// (Playwright from npm, with its browsers: npx playwright install)
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const dir = process.argv[2];
const names = process.argv.length > 3 ? process.argv.slice(3) : ['chromium', 'firefox', 'webkit'];
const types = { '.js': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html' };
const server = createServer(async (req, res) => {
	const p = path.join(dir, decodeURIComponent(new URL(req.url, 'http://x').pathname));
	try {
		const b = req.url === '/' ? Buffer.from('<!doctype html><title>test</title>') : await readFile(p);
		res.writeHead(200, { 'content-type': req.url === '/' ? 'text/html' : types[path.extname(p)] || 'application/octet-stream' });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
}).listen(0);
const port = server.address().port;

const code = 'class Main {\n\tstatic function main() {\n\t\tvar a = [for (i in 0...5) i * i];\n\t\ttrace("Hello " + a);\n\t\ttry throw "oops" catch (e:String) Sys.println("caught " + e);\n\t\tSys.println(haxe.Json.stringify({ok: true}));\n\t}\n}\n';

async function inPage(code) {
	const w = new Worker('worker.js');
	const replies = [];
	let wake = null;
	w.onmessage = (e) => { replies.push(e.data); if (wake) wake(); };
	w.onerror = (e) => { replies.push({ type: 'failed', message: e.message }); if (wake) wake(); };
	async function until(pred) {
		while (true) {
			const i = replies.findIndex(pred);
			if (i >= 0) return replies.splice(i, 1)[0];
			await new Promise((r) => (wake = r));
		}
	}
	const log = [];
	const t0 = performance.now();
	w.postMessage({ type: 'module', module: await WebAssembly.compileStreaming(fetch('hih.wasm')) });
	w.postMessage({ type: 'warmup' });
	const ready = await until((r) => r.type === 'ready' || r.type === 'failed');
	log.push(`ready ${ready.type} ${ready.message ?? ''} ${Math.round(performance.now() - t0)} ms`);
	if (ready.type === 'failed') return log;
	// (three times: the engines optimize the module's code while it runs)
	for (let k = 0; k < 3; k++) {
		w.postMessage({ type: 'compile', id: 1, mode: 'run', main: 'Main', file: 'Main.hx', code });
		const done = await until((r) => r.type === 'done' || r.type === 'failed');
		for (const r of replies.splice(0)) if (k == 0) log.push(`${r.type} ${r.text}`);
		log.push(`run ${done.status} ${Math.round(done.ms)} ms ${done.message ?? ''}`);
	}
	w.postMessage({ type: 'compile', id: 2, mode: 'hxb', main: 'Main', file: 'Main.hx', code });
	const hxb = await until((r) => r.type === 'done' || r.type === 'failed');
	replies.splice(0);
	log.push(`hxb ${hxb.status} ${hxb.zip ? hxb.zip.byteLength + ' bytes' : hxb.message} ${Math.round(hxb.ms)} ms`);
	w.postMessage({ type: 'check', id: 3, main: 'Main', file: 'Main.hx', code: code.replace('trace(', 'trace(undefinedThing + ') });
	const check = await until((r) => r.type === 'check' || r.type === 'failed');
	log.push(`check ${check.status} ${JSON.stringify(check.output)}`);
	const at = code.indexOf(' + a') + 4;
	const dcode = code.slice(0, at) + '.' + code.slice(at);
	w.postMessage({ type: 'display', id: 4, main: 'Main', file: 'Main.hx', code: dcode,
		request: { jsonrpc: '2.0', id: 1, method: 'display/completion', params: { file: '/work/Main.hx', offset: at + 1, wasAutoTriggered: true } } });
	const disp = await until((r) => r.type === 'display' || r.type === 'failed');
	log.push(`display ${disp.status} ${(disp.output ?? disp.message).slice(0, 120)}`);
	w.terminate();
	return log;
}

let failed = 0;
for (const name of names) {
	let browser;
	try {
		browser = await pw[name].launch();
		const page = await browser.newPage();
		await page.goto(`http://localhost:${port}/`);
		const log = await page.evaluate(inPage, code);
		console.log(`== ${name} ${browser.version()}`);
		for (const l of log) console.log('  ' + l);
		if (!log.some((l) => l.startsWith('run 0')) || !log.some((l) => l.startsWith('hxb 0'))) failed++;
	} catch (e) {
		console.log(`== ${name}: ${e.message.split('\n')[0]}`);
		failed++;
	} finally {
		if (browser) await browser.close();
	}
}
server.close();
process.exit(failed ? 1 : 0);
