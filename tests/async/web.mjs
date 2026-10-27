// helder.async's browser loop under node: the module run by
// src/helder/os/browser.mjs with src/helder/async/imports.mjs (node has
// fetch, setTimeout and setImmediate), the page's files served from
// tests/async by a local HTTP server; exits with the program's code.
//   node tests/async/web.mjs <module.wasm>
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { run } from '../../src/helder/os/browser.mjs';
import imports from '../../src/helder/async/imports.mjs';

const dir = path.dirname(new URL(import.meta.url).pathname);
const server = http.createServer((req, res) => {
	const f = path.join(dir, path.normalize(req.url).replace(/^\/+/, ''));
	if (!fs.existsSync(f)) return res.writeHead(404).end();
	res.writeHead(200).end(fs.readFileSync(f));
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}/`;
const { host } = await run(fs.readFileSync(process.argv[2]), { imports: [imports], base });
const t0 = Date.now();
while (host.exitCode === null && Date.now() - t0 < 20000) await new Promise((r) => setTimeout(r, 10));
server.close();
if (host.exitCode === null) console.error('web.mjs: the program did not exit');
process.exit(host.exitCode ?? 1);
