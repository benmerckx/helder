// helder.compiler.web in headless Chromium (the compiler-web lane's second
// half): the worker (worker.mjs, client.mjs) loads build.mjs's toolchain
// as a page would (brotli where the page accepts it), builds todo and
// ts-todo to wasm32 on the page, runs each in a frame of its own
// (preview.mjs: helder.os's browser imports and helder dev's), reads its
// view (Ui.getTree through the devtools protocol), then makes a literal
// edit (patched in the running program, no build) and a structural one (a
// build, swapped in) and reads the view again; then prints the numbers:
// the cold start, the first builds, a warm build, an edit, the memory and
// the downloads.
//   node tests/compiler-web/browser.mjs [dir: build.mjs's output, bin/compiler-web]
// (Playwright from npm, with Chromium: npx playwright install chromium)
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../..');
const dir = path.resolve(process.argv[2] ?? path.join(repo, 'bin/compiler-web'));
const manifest = JSON.parse(readFileSync(path.join(dir, 'manifest.json'), 'utf8'));
const font = ['/usr/share/fonts/truetype/dejavu', '/usr/share/fonts/TTF', '/usr/share/fonts/dejavu'].map((d) => path.join(d, 'DejaVuSans.ttf')).find((f) => existsSync(f));

const HARNESS = `<!doctype html><meta charset="utf-8"><title>compiler-web</title><body><script type="module">
import { CompilerClient } from '/src/helder/compiler/web/client.mjs';
window.client = new CompilerClient(new Worker('/src/helder/compiler/web/worker.mjs', { type: 'module' }));
window.client.onLog = (t) => console.log('[compiler] ' + t);
window.ready = true;
</script>`;
const PREVIEW = `<!doctype html><meta charset="utf-8"><title>preview</title><style>body { margin: 0 }</style><body><script type="module">
import { Preview } from '/src/helder/compiler/web/preview.mjs';
const fonts = ${font ? "[await (await fetch('/fonts/DejaVuSans.ttf')).arrayBuffer()]" : '[]'};
window.preview = new Preview({ base: '/src/helder/', fonts, stdout: (s) => console.log('[preview] ' + s), stderr: (s) => console.log('[preview] ' + s) });
window.ready = true;
</script>`;
const types = { '.mjs': 'text/javascript', '.js': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html', '.json': 'application/json', '.ttf': 'font/ttf' };
let served = 0;
const server = createServer(async (req, res) => {
	const p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
	try {
		if (p === '/' || p === '/preview.html') {
			res.writeHead(200, { 'content-type': 'text/html' });
			return res.end(p === '/' ? HARNESS : PREVIEW);
		}
		let file = p === '/fonts/DejaVuSans.ttf' ? font
			: p.startsWith('/compiler-web/') ? path.join(dir, p.slice(14))
			: p.startsWith('/src/') ? path.join(repo, p) : null;
		if (!file || (file !== font && !path.resolve(file).startsWith(p.startsWith('/compiler-web/') ? dir : repo))) throw new Error('not served');
		const headers = { 'content-type': types[path.extname(file)] ?? 'application/octet-stream' };
		// (the toolchain's modules as brotli where the browser takes it, as a server would send them)
		if (/\bbr\b/.test(req.headers['accept-encoding'] ?? '') && existsSync(file + '.br') && p.startsWith('/compiler-web/')) {
			file += '.br';
			headers['content-encoding'] = 'br';
		}
		const b = await readFile(file);
		served += b.length;
		headers['content-length'] = b.length;
		res.writeHead(200, headers);
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
}).listen(0);
const url = `http://localhost:${server.address().port}/`;

let failed = 0;
const check = (what, ok, detail) => {
	if (!ok) failed++;
	console.log(`browser.mjs: ${ok ? 'ok' : 'FAIL'}: ${what}${!ok && detail !== undefined ? ': ' + String(typeof detail === 'string' ? detail : JSON.stringify(detail)).slice(0, 3000) : ''}`);
};

const browser = await pw.chromium.launch({ args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'] });
console.log(`browser.mjs: chromium ${browser.version()}`);
const page = await browser.newPage();
const logs = [];
page.on('console', (m) => {
	logs.push(m.text());
	if (process.env.VERBOSE) console.log('  ' + m.text());
});
page.on('pageerror', (e) => console.log('browser.mjs: page error: ' + e.message));
await page.goto(url);
await page.waitForFunction(() => window.ready);

const numbers = { chromium: browser.version() };
try {
	const init = await page.evaluate(() => window.client.init({ assets: { base: new URL('/compiler-web/', location.href).href }, persist: false }));
	check(`the worker started (${init.ms.total} ms: download ${init.ms.download}, compile ${init.ms.compile}, unpack ${init.ms.unpack}, warm ${init.ms.warm})`, init.protocol === 1 && init.versions.typescript === 'wasip1', init);
	numbers.start = init.ms;
	numbers.downloaded = init.bytes;

	const read = (ex) => Object.fromEntries(readdirSync(path.join(repo, 'examples', ex)).filter((f) => statSync(path.join(repo, 'examples', ex, f)).isFile())
		.map((f) => [`/work/${ex}/${f}`, readFileSync(path.join(repo, 'examples', ex, f), 'utf8')]));
	const examples = [
		{ ex: 'todo', file: '/work/todo/Todo.hx', title: '<text font-size={28} font-weight={700} color="#3b82f6">todos</text>' },
		{ ex: 'ts-todo', file: '/work/ts-todo/app.tsx', title: '<text font-size={28} font-weight={700} color="#3b82f6">todos</text>' },
	];
	numbers.examples = {};
	for (const { ex, file, title } of examples) {
		const n = (numbers.examples[ex] = {});
		const files = read(ex);
		const source = files[file];
		await page.evaluate((files) => window.client.write(files), files);
		const b = await page.evaluate(async (ex) => {
			const r = await window.client.build('/work/' + ex);
			window.built = r;
			return { ok: r.ok, ms: r.ms, tsgoMs: r.tsgoMs, bytes: r.wasm?.length ?? 0, messages: r.messages };
		}, ex);
		check(`${ex}: built on the page (${b.ms} ms, ${b.bytes} bytes)`, b.ok && b.bytes > 0, b.messages);
		n.build = b.ms;
		n.bytes = b.bytes;
		if (!b.ok) continue;
		// (a frame of its own, the build run in it, its view read through the devtools protocol)
		const frame = await page.evaluate((ex) => new Promise((resolve) => {
			const f = document.createElement('iframe');
			f.id = 'preview-' + ex;
			f.style.cssText = 'width: 480px; height: 560px; border: 0';
			f.src = '/preview.html';
			f.onload = () => resolve(true);
			document.body.append(f);
		}), ex);
		const fh = await (await page.$('#preview-' + ex)).contentFrame();
		await fh.waitForFunction(() => window.ready);
		const ran = await page.evaluate(async (ex) => {
			const w = document.getElementById('preview-' + ex).contentWindow;
			const t0 = performance.now();
			try {
				await w.preview.run(window.built);
			} catch (e) {
				return { error: String(e?.stack ?? e) };
			}
			window.client.running = (request) => w.preview.devtools(request);
			return { ms: Math.round(performance.now() - t0) };
		}, ex);
		check(`${ex}: runs in its frame (${ran.ms} ms)`, !ran.error, ran.error);
		if (ran.error) continue;
		await fh.waitForFunction(() => window.preview.frames > 0, null, { timeout: 20000 }).catch(() => {});
		const tree = () => page.evaluate((ex) => document.getElementById('preview-' + ex).contentWindow.preview.devtools({ method: 'Ui.getTree' }).then((r) => JSON.stringify(r?.result ?? r)), ex);
		const t1 = await tree();
		check(`${ex}: its view read (Ui.getTree): the empty list's text`, t1.includes('Nothing here.'), t1.slice(0, 400));

		// a literal edit: patched in the running program, nothing built
		// (the title's colour: an attribute, bound as any read is)
		const literal = source.replace('color="#3b82f6">todos', 'color="#ef4444">todos');
		const e1 = await page.evaluate(([file, text]) => window.client.edit({ [file]: text }), [file, literal]);
		check(`${ex}: a literal edit patched, no build (${e1.ms} ms)`, e1.kind === 'patched', e1);
		n.literalEdit = e1.ms;
		await fh.waitForFunction((f) => window.preview.frames > f, await fh.evaluate(() => window.preview.frames), { timeout: 5000 }).catch(() => {});
		const t2 = await tree();
		check(`${ex}: the patched colour shown`, t2.includes('ef4444') && !t2.includes('3b82f6'), t2.slice(0, 400));

		// a structural edit: a build's, swapped in
		const patched = title.replace('#3b82f6', '#ef4444');
		const structural = literal.replace(patched, patched + '<text tag="added">a structural edit</text>');
		const e2 = await page.evaluate(([file, text]) => window.client.edit({ [file]: text }), [file, structural]);
		check(`${ex}: a structural edit is a build's (${e2.why})`, e2.kind === 'build', e2);
		const b2 = await page.evaluate(async ([ex, file]) => {
			const r = await window.client.build('/work/' + ex, { changed: [file] });
			if (!r.ok) return { ok: false, messages: r.messages };
			const w = document.getElementById('preview-' + ex).contentWindow;
			const t0 = performance.now();
			await w.preview.swap(r);
			return { ok: true, ms: r.ms, swap: Math.round(performance.now() - t0) };
		}, [ex, file]);
		check(`${ex}: built again warm (${b2.ms} ms) and swapped in (${b2.swap} ms)`, b2.ok, b2.messages);
		n.warmBuild = b2.ms;
		n.swap = b2.swap;
		await fh.waitForFunction(() => window.preview.frames > 0 && window.preview.swaps > 0, null, { timeout: 20000 }).catch(() => {});
		const t3 = await tree();
		check(`${ex}: the new view shown, the patched colour kept`, t3.includes('a structural edit') && t3.includes('ef4444'), t3.slice(0, 400));
		await page.evaluate((ex) => {
			window.client.running = null;
			const f = document.getElementById('preview-' + ex);
			f.contentWindow.preview.dispose();
			f.remove();
		}, ex);
	}
	const stats = await page.evaluate(() => window.client.stats());
	numbers.memory = stats.memory;
	numbers.heap = await page.evaluate(() => performance.memory ? { used: performance.memory.usedJSHeapSize } : null);
} catch (e) {
	check('the run', false, e?.stack ?? e);
	console.log(logs.slice(-30).join('\n'));
}
numbers.files = manifest.files;
console.log('browser.mjs: numbers ' + JSON.stringify(numbers));
await browser.close();
server.close();
if (failed) {
	console.log(`browser.mjs: ${failed} failed`);
	process.exit(1);
}
