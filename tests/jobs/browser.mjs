// helder.jobs in headless Chromium: JobsWeb.wasm run by
// src/helder/os/browser.mjs with os's, async's and jobs' imports (Web
// Workers instantiating the same module) on a page served from the
// repository; "JobsWeb: hide" hides the canvas (no frames, as a hidden
// tab), "JobsWeb: done <failures>" ends it.
//   node tests/jobs/browser.mjs <JobsWeb.wasm>
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const pw = require('playwright');
const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '../..');
const wasm = path.resolve(process.argv[2]);
const page = `<!doctype html><canvas id="c" width="64" height="64"></canvas><script type="module">
import { run } from '/src/helder/os/browser.mjs';
const log = (l) => {
	console.log(l);
	if (l === 'JobsWeb: hide') document.getElementById('c').style.display = 'none';
};
await run('/module.wasm', { canvas: 'c', imports: ['/src/helder/os/imports.mjs', '/src/helder/async/imports.mjs', '/src/helder/jobs/imports.mjs'], stdout: log, stderr: log });
</script>`;
const types = { '.mjs': 'text/javascript', '.js': 'text/javascript', '.wasm': 'application/wasm' };
const server = createServer(async (req, res) => {
	const url = new URL(req.url, 'http://x').pathname;
	try {
		const body = url === '/' ? page : await readFile(url === '/module.wasm' ? wasm : path.join(root, url));
		res.writeHead(200, { 'content-type': url === '/' ? 'text/html' : types[path.extname(url)] ?? 'application/octet-stream' }).end(body);
	} catch {
		res.writeHead(404).end();
	}
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const browser = await pw.chromium.launch();
const p = await browser.newPage();
const out = [];
const done = new Promise((resolve) => p.on('console', (m) => {
	out.push(m.text());
	const d = /^JobsWeb: done (\d+)/.exec(m.text());
	if (d) resolve(Number(d[1]));
}));
p.on('pageerror', (e) => out.push('page error: ' + e.message));
await p.goto(`http://127.0.0.1:${server.address().port}/`);
const failures = await Promise.race([done, new Promise((r) => setTimeout(() => r(-1), 30000))]);
console.log(out.join('\n'));
await browser.close();
server.close();
process.exit(failures === 0 ? 0 : 1);
