// Native text editors in a browser (make ui-web-check): WebField.wasm in
// headless Chromium, its field and text area the page's own input and
// textarea over the canvas (Ui.platform: WebViews), driven by real events:
// each editor placed over its node's box; typing edits the bound signal;
// Enter submits the field; Tab and Shift+Tab move the program's focus
// between the editors and the drawn widgets (the page's focus following);
// a newline typed in the text area; the program's own change shown in the
// editor; an editor hidden while the select's list covers it, shown again
// when it closes; Tab from a drawn field (its host drawn, typed in through
// the window's text input) into a native one, which keeps the focus.
//   node packages/ui/test/web-field.mjs <WebField.wasm> [screenshot.png]
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const [wasm, shot] = process.argv.slice(2);
const files = {
	'/field.wasm': wasm,
	'/os/browser.mjs': path.join(here, '../../os/browser.mjs'),
	'/os/imports.mjs': path.join(here, '../../os/imports.mjs'),
	'/gfx/imports.mjs': path.join(here, '../../gfx/imports.mjs'),
	'/text/imports.mjs': path.join(here, '../../text/imports.mjs'),
	'/ui/imports.mjs': path.join(here, '../imports.mjs'),
	'/DejaVuSans.ttf': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
	'/DejaVuSans-Bold.ttf': '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
};
const types = { '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.ttf': 'font/ttf' };
const page = `<!doctype html><title>Fields</title><body style="margin:0">
<div style="height: 30px"></div>
<canvas id="c" style="width: 420px; height: 320px; display: block; margin-left: 10px"></canvas>
<script type="module">
import { run } from './os/browser.mjs';
window.log = [];
window.start = async () => {
	window.r = run('field.wasm', { imports: ['os/imports.mjs', 'gfx/imports.mjs', 'text/imports.mjs', 'ui/imports.mjs'], canvas: 'c', gfx: 'webgl2',
		fonts: ['DejaVuSans.ttf', 'DejaVuSans-Bold.ttf'], stdout: (s) => window.log.push(s), stderr: (s) => window.log.push('stderr: ' + s) });
	window.result = await window.r;
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
const browser = await pw.chromium.launch({ args: ['--use-angle=swiftshader'] });
const p = await browser.newPage({ viewport: { width: 500, height: 420 } });
const errors = [];
p.on('pageerror', (e) => errors.push(e.message));
p.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
await p.goto(url);
await p.evaluate(() => window.start());
await p.waitForFunction(() => window.log.some((l) => l.startsWith('boxes ')), null, { timeout: 15000 });
const settle = () => p.waitForTimeout(150);
await settle();
// the latest line: the boxes (centres, in the page) and the state
const state = async () => {
	const line = (await p.evaluate(() => window.log)).filter((l) => l.startsWith('boxes ')).pop();
	const [boxes, ...rest] = line.slice(6).split(' | ');
	const m = {};
	for (const part of boxes.split(' ')) {
		const [k, v] = part.split('=');
		const [x, y, w, h] = v.split(',').map(Number);
		m[k] = { x: x + 10, y: y + 30, w, h };
	}
	const s = {};
	for (const r of rest) {
		const i = r.indexOf('=');
		s[r.slice(0, i)] = r.slice(i + 1);
	}
	return { m, s };
};
const editor = (tag) => p.evaluate((t) => {
	const e = document.querySelector(t);
	if (!e) return null;
	const r = e.getBoundingClientRect();
	return { x: r.x, y: r.y, w: r.width, h: r.height, shown: getComputedStyle(e).display !== 'none', value: e.value, focused: document.activeElement === e, font: getComputedStyle(e).fontFamily };
}, tag);
const results = [];
const check = (what, ok, detail) => results.push({ what, ok, detail });
let { m } = await state();
let input = await editor('input[data-hxmc-editor]'), area = await editor('textarea[data-hxmc-editor]');
check('two editors', input && area, JSON.stringify({ input, area }));
check('the field\'s editor inside its box', input && input.shown && input.x > m.name.x && input.x + input.w < m.name.x + m.name.w && input.y >= m.name.y && input.y + input.h <= m.name.y + m.name.h + 0.5,
	JSON.stringify({ input, box: m.name }));
check('in the field\'s font', input && input.font.includes('DejaVu Sans'), input && input.font);
await p.mouse.click(input.x + 5, input.y + input.h / 2);
await settle();
await p.keyboard.type('Ada');
await settle();
let { s } = await state();
check('typed in the editor, the signal follows', s.name === 'Ada' && s.focus === 'name', JSON.stringify(s));
await p.keyboard.press('Enter');
await settle();
({ s } = await state());
check('Enter submits', s.submitted === 'Ada', JSON.stringify(s));
await p.keyboard.press('Tab');
await settle();
({ s } = await state());
area = await editor('textarea[data-hxmc-editor]');
check('Tab to the text area: the program\'s focus and the page\'s', s.focus === 'notes' && area.focused, JSON.stringify({ s, area }));
await p.keyboard.type('one');
await p.keyboard.press('Enter');
await p.keyboard.type('two');
await settle();
({ s } = await state());
check('a newline in the text area', s.notes === 'one\\ntwo', JSON.stringify(s));
await p.keyboard.press('Tab');
await settle();
({ s } = await state());
area = await editor('textarea[data-hxmc-editor]');
check('Tab on to a drawn button', s.focus === 'reset' && !area.focused, JSON.stringify(s));
await p.keyboard.press('Shift+Tab');
await settle();
({ s } = await state());
area = await editor('textarea[data-hxmc-editor]');
check('Shift+Tab back into the text area', s.focus === 'notes' && area.focused, JSON.stringify({ s, area }));
({ m } = await state());
await p.mouse.click(m.reset.x + m.reset.w / 2, m.reset.y + m.reset.h / 2);
await settle();
input = await editor('input[data-hxmc-editor]');
check('the program\'s change in the editor', input.value === 'Reset', JSON.stringify(input));
await p.mouse.click(m.fruit.x + m.fruit.w / 2, m.fruit.y + m.fruit.h / 2);
await settle();
input = await editor('input[data-hxmc-editor]');
check('covered by the select\'s list: hidden', !input.shown, JSON.stringify(input));
await p.keyboard.press('Escape');
await settle();
input = await editor('input[data-hxmc-editor]');
check('the list closed: shown again', input.shown, JSON.stringify(input));
if (shot) await p.screenshot({ path: shot });
// a drawn field typed in (the window's text input), then Tab into the native one: its focus kept
({ m } = await state());
await p.mouse.click(m.drawn.x + m.drawn.w / 2, m.drawn.y + m.drawn.h / 2);
await settle();
await p.keyboard.type('hi');
await settle();
({ s } = await state());
check('a drawn field (host drawn) typed in', s.drawn === 'hi' && s.focus === 'drawn' && !(await editor('input[data-hxmc-editor]')).focused, JSON.stringify(s));
await p.keyboard.press('Tab');
await settle();
({ s } = await state());
input = await editor('input[data-hxmc-editor]');
check('Tab from the drawn field to the native one: its editor keeps the page\'s focus', s.focus === 'name' && input.focused, JSON.stringify({ s, input }));
check('no errors', errors.length === 0, errors.join(' | '));
const failed = results.filter((r) => !r.ok);
for (const r of failed) console.log(`web-field.mjs: FAIL: ${r.what}: ${r.detail}`);
console.log(`web-field.mjs: ${results.length} checks` + (failed.length ? `, ${failed.length} FAILED` : ', ok'));
await browser.close();
server.close();
process.exit(failed.length ? 1 : 0);
