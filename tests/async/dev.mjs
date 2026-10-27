// The async-dev example end to end, driven by node: started on a directory
// of its own and a child process, a file fetched, a WebSocket connected
// (node's), a file changed and its message awaited, the child's output
// checked (printed and sent to the socket), then GET /quit and a clean exit.
//   node tests/async/dev.mjs <AsyncDev executable> <work directory>
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const [exe, work] = process.argv.slice(2);
const dir = path.join(work, 'site');
fs.rmSync(dir, { recursive: true, force: true });
fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(path.join(dir, 'index.html'), '<p>async-dev</p>');
fs.writeFileSync(path.join(dir, 'style.css'), 'p {}');

const fail = (m) => { console.error('dev.mjs: ' + m); child.kill(); process.exit(1); };
const timer = setTimeout(() => fail('timed out; output:\n' + out), 20000);
process.on('uncaughtException', (e) => fail(String(e?.message ?? e)));
process.on('unhandledRejection', (e) => fail(String(e?.message ?? e)));
const child = spawn(exe, [dir, '0', 'sh', '-c', 'echo child started; sleep 0.3; echo child done'], { stdio: ['ignore', 'pipe', 'inherit'] });
let out = '';
const waiters = [];
child.stdout.on('data', (d) => {
	out += d;
	for (const w of waiters.slice()) if (w.re.test(out)) { waiters.splice(waiters.indexOf(w), 1); w.resolve(out.match(w.re)); }
});
const waitFor = (re) => new Promise((resolve) => { if (re.test(out)) resolve(out.match(re)); else waiters.push({ re, resolve }); });

const [, port] = await waitFor(/listening on http:\/\/127\.0\.0\.1:(\d+)\//);
const base = `http://127.0.0.1:${port}`;
const page = await (await fetch(base + '/')).text();
if (page !== '<p>async-dev</p>') fail('GET /: ' + page);
const css = await fetch(base + '/style.css');
if (css.headers.get('content-type') !== 'text/css; charset=utf-8') fail('a type: ' + css.headers.get('content-type'));
if ((await fetch(base + '/nothing')).status !== 404) fail('not a 404');

const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
const messages = [];
const got = (f) => new Promise((resolve) => {
	const check = () => { const m = messages.find(f); if (m) resolve(m); else setTimeout(check, 10); };
	check();
});
ws.onmessage = (e) => messages.push(JSON.parse(e.data));
await new Promise((r) => { ws.onopen = r; ws.onerror = () => fail('the WebSocket failed'); });
// (the watcher's snapshot is taken: change a file)
await new Promise((r) => setTimeout(r, 150));
fs.writeFileSync(path.join(dir, 'style.css'), 'p { color: red }');
const m = await got((m) => m.changed);
if (m.changed.length !== 1 || !m.changed[0].endsWith('style.css')) fail('changed: ' + JSON.stringify(m));
await waitFor(/\[child\] child started\n[^]*\[child\] child done\n\[child\] exited with 0/);
await got((m) => m.out === 'child done');
if (!messages.some((m) => m.out === 'child started') && !out.includes('[child] child started')) fail('the child\'s first line');

const bye = await (await fetch(base + '/quit')).text();
if (bye !== 'bye\n') fail('quit: ' + bye);
const code = await new Promise((r) => child.on('exit', r));
await new Promise((r) => { if (ws.readyState === WebSocket.CLOSED) r(); else ws.onclose = r; setTimeout(r, 1000); });
clearTimeout(timer);
if (code !== 0) fail('exit code ' + code + '; output:\n' + out);
if (!/stopped after/.test(out)) fail('no clean stop:\n' + out);
console.log('async-dev: served, watched, streamed, stopped (' + out.trim().split('\n').length + ' lines of output)');
