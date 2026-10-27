// helder.async's browser loop in headless Chromium: WebTest.wasm run by
// src/helder/os/browser.mjs with src/helder/async/imports.mjs on a page
// served from the repository, its output read from the console.
//   node tests/async/browser.mjs <module.wasm>
// (Playwright from npm, with Chromium: npx playwright install chromium)
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const pw = require('playwright');
const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '../..');
const wasm = path.resolve(process.argv[2]);
const page = `<!doctype html><script type="module">
import { run } from '/src/helder/os/browser.mjs';
const { host } = await run('/module.wasm', { imports: ['/src/helder/async/imports.mjs'], stdout: (l) => console.log(l), stderr: (l) => console.log(l) });
const wait = () => host.exitCode === null ? setTimeout(wait, 10) : console.log('exit ' + host.exitCode);
wait();
</script>`;
const types = { '.mjs': 'text/javascript', '.js': 'text/javascript', '.wasm': 'application/wasm', '.txt': 'text/plain' };
const server = createServer(async (req, res) => {
	const url = new URL(req.url, 'http://x').pathname;
	try {
		const body = url === '/' ? page : await readFile(url === '/module.wasm' ? wasm : url === '/hello.txt' ? path.join(root, 'tests/async/hello.txt') : path.join(root, url));
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
	if (m.text().startsWith('exit ')) resolve(Number(m.text().slice(5)));
}));
p.on('pageerror', (e) => out.push('page error: ' + e.message));
await p.goto(`http://127.0.0.1:${server.address().port}/`);
const code = await Promise.race([done, new Promise((r) => setTimeout(() => r(-1), 20000))]);
console.log(out.join('\n'));
await browser.close();
server.close();
process.exit(code === 0 ? 0 : 1);
