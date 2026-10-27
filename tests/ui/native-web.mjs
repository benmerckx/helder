// helder.ui.native's DOM backend (npm test -- ui-web): the native form
// (examples/NativeForm.hx) for wasm32-wasi in headless Chromium, its
// controls the page's own (button, input, progress, spans for text) placed
// at the layout's positions; driven by real input (typing, clicks, a range
// moved) with the signals following, checked through the page.
//   node tests/ui/native-web.mjs <NativeForm.wasm> [out dir]
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const [wasm, out] = process.argv.slice(2);
const files = {
	'/form.wasm': wasm,
	'/os/browser.mjs': path.join(here, '../../src/helder/os/browser.mjs'),
	'/ui/imports.mjs': path.join(here, '../../src/helder/ui/imports.mjs'),
};
const types = { '.mjs': 'text/javascript', '.wasm': 'application/wasm' };
const page = `<!doctype html><title>NativeForm</title><body style="margin:0; font-family: sans-serif">
<div id="form" style="width: 440px; height: 380px"></div>
<script type="module">
import { run } from './os/browser.mjs';
window.log = [];
window.start = async () => {
	window.result = await run('form.wasm', { imports: ['ui/imports.mjs'], nativeContainer: 'form',
		stdout: (s) => window.log.push(s), stderr: (s) => window.log.push('stderr: ' + s) });
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
const browser = await pw.chromium.launch();
const p = await browser.newPage({ viewport: { width: 500, height: 420 } });
const errors = [];
p.on('pageerror', (e) => errors.push(e.message));
p.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
await p.goto(url);
await p.evaluate(() => window.start());
await p.waitForSelector('#form input[type=text]');
const settle = () => p.waitForTimeout(100);
const failures = [];
const check = (what, ok, detail) => ok || failures.push(what + (detail ? ': ' + detail : ''));
const text = (sel) => p.$eval(sel, (e) => e.textContent);
const spans = () => p.$$eval('#form span', (es) => es.map((e) => e.textContent));
const box = (sel) => p.$eval(sel, (e) => { const r = e.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; });
await settle();
check('the greeting', (await spans()).includes('Who are you?'), (await spans()).join('|'));
// typing into the page's input
await p.fill('#form input[type=text]', 'Ada');
await settle();
check('typed text reaches the signal', (await spans()).includes('Hello, Ada!'), (await spans()).join('|'));
const submit = await p.$('#form button');
check('the button disabled until agreed', await submit.isDisabled());
await p.click('#form input[type=checkbox]');
await settle();
check('a checkbox', !(await submit.isDisabled()));
await submit.click();
await submit.click();
await settle();
const buttons = await p.$$eval('#form button', (es) => es.map((e) => e.textContent));
check('clicks', buttons[1] === 'Submitted 2 times', buttons.join('|'));
// a range moved (its input event, as dragging gives it)
await p.$eval('#form input[type=range]', (e) => { e.value = '0.75'; e.dispatchEvent(new Event('input')); });
await settle();
check('a slider', (await spans()).includes('75%'), (await spans()).join('|'));
check('the progress bar follows', (await p.$eval('#form progress', (e) => e.value)) === 0.75);
// placed by the layout: the two buttons side by side, 8 apart, at their own widths
const b1 = await box('#form button:nth-of-type(1)'), b2 = await box('#form button:nth-of-type(2)');
check('buttons laid out in a row, 8 apart', Math.abs(b2.x - (b1.x + b1.w) - 8) < 1.5 && Math.abs(b1.y - b2.y) < 0.5, JSON.stringify([b1, b2]));
const field = await box('#form input[type=text]');
check('the field stretched across the padding box', Math.abs(field.x - 16) < 1 && Math.abs(field.w - 408) < 1, JSON.stringify(field));
// a longer label: measured again, the row laid out again
await p.evaluate(() => { for (let i = 0; i < 8; i++) document.querySelector('#form button').click(); });
await settle();
const b2b = await box('#form button:nth-of-type(2)');
check('a new label measured again', b2b.w > b2.w - 0.5, JSON.stringify([b2, b2b]));
if (out) await writeFile(path.join(out, 'native-web.png'), await p.screenshot());
check('no errors', errors.length === 0, errors.join('; '));
console.log(`native-web.mjs: ${failures.length ? 'FAILED: ' + failures.join('; ') : 'ok'}`);
await browser.close();
server.close();
process.exit(failures.length ? 1 : 0);
