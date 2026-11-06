// helder.ui's ARIA mirror in a browser (bun run test ui-web): WebAccessPage.wasm
// (AccessFixture's controls) in headless Chromium, the page's accessibility
// tree read as assistive technology reads it: Chromium's own tree through
// the DevTools protocol (roles, names and states as Chromium computes them:
// Playwright's ARIA snapshot leaves out a canvas's fallback content), with
// the mirror's ARIA counts and indices (a grid's rows and columns, a cell's
// place, a list item's place in its set, which the protocol does not
// give); then the mirror's
// elements clicked as a screen reader clicks them (a disclosure expanded, a
// row selected, the Save button), the program's state and the tree after.
//   node tests/ui/web-access.mjs <WebAccessPage.wasm>
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
const files = {
	'/access.wasm': wasm,
	'/os/browser.mjs': path.join(here, '../../src/helder/os/browser.mjs'),
	'/os/imports.mjs': path.join(here, '../../src/helder/os/imports.mjs'),
	'/gfx/imports.mjs': path.join(here, '../../src/helder/gfx/imports.mjs'),
	'/text/imports.mjs': path.join(here, '../../src/helder/text/imports.mjs'),
	'/ui/imports.mjs': path.join(here, '../../src/helder/ui/imports.mjs'),
	'/DejaVuSans.ttf': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
	'/DejaVuSans-Bold.ttf': '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
};
const types = { '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.ttf': 'font/ttf' };
const page = `<!doctype html><title>Access</title><body style="margin:0">
<canvas id="c" style="width: 400px; height: 640px; display: block"></canvas>
<script type="module">
import { run } from './os/browser.mjs';
window.log = [];
window.start = async () => {
	window.r = run('access.wasm', { imports: ['os/imports.mjs', 'gfx/imports.mjs', 'text/imports.mjs', 'ui/imports.mjs'], canvas: 'c', gfx: 'webgl2',
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
const browser = await pw.chromium.launch({ args: ['--use-angle=swiftshader', '--force-renderer-accessibility'] });
const p = await browser.newPage({ viewport: { width: 420, height: 660 } });
const errors = [];
p.on('pageerror', (e) => errors.push(e.message));
p.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
let failed = 0, checks = 0;
const check = (what, ok, detail) => {
	checks++;
	if (!ok) {
		failed++;
		console.log(`web-access.mjs: FAIL: ${what}${detail === undefined ? '' : ': ' + detail}`);
	}
};
try {
	await p.goto(url);
	await p.evaluate(() => window.start());
	await p.waitForFunction(() => window.log.some((l) => l.startsWith('state ')), null, { timeout: 20000 });
	await p.waitForTimeout(300);
	const state = async () => (await p.evaluate(() => window.log)).filter((l) => l.startsWith('state ')).pop();
	// Chromium's accessibility tree (what a screen reader gets; Playwright's
	// ARIA snapshot leaves the canvas's fallback content out, having no
	// boxes): each node as role "name" [states]
	const cdp = await p.context().newCDPSession(p);
	const snapshot = async () => {
		const ax = (await cdp.send('Accessibility.getFullAXTree')).nodes.filter((n) => !n.ignored);
		const lines = ax.map((n) => {
			const states = (n.properties ?? []).filter((x) => ['expanded', 'selected', 'checked', 'readonly', 'disabled'].includes(x.name))
				.map((x) => `[${x.name}=${x.value.value}]`).join(' ');
			return `${n.role?.value} "${n.name?.value ?? ''}"${states ? ' ' + states : ''}`;
		});
		return { ax, text: lines.join('\n') };
	};
	const first = await snapshot();
	const ax = first.ax;
	for (const want of ['button "Save"', 'checkbox "Remember" [checked=false]', 'slider "Volume"', 'textbox "Name"', 'textbox "Code" [readonly=true]', 'textbox "Notes"',
		'button "More" [expanded=false]', 'list "Fruits"', 'listitem "Pear"', 'grid "Mail"', 'row "Bob Lunch" [selected=false]', 'gridcell "Lunch"',
		'columnheader "Subject"', 'tablist ""', 'tab "General" [selected=true]', 'StaticText "Ready"'])
		check(`the tree: ${want}`, first.text.split('\n').some((l) => l.startsWith(want)), want);
	if (failed) console.log(first.text);
	const node = (role, name) => ax.find((n) => n.role?.value === role && n.name?.value === name);
	const prop = (n, k) => n?.properties?.find((x) => x.name === k)?.value?.value;
	// a screen reader's clicks on the mirror's elements
	const click = (role, name) => p.evaluate(([r, n]) => {
		const e = [...document.querySelectorAll(`#c [role=${r}]`)].find((x) => x.getAttribute('aria-label') === n);
		if (!e) return false;
		e.click();
		return true;
	}, [role, name]);
	check('More clicked', await click('button', 'More'));
	await p.waitForTimeout(300);
	check('expanded: the program', (await state()).includes('open=true'), await state());
	const after = (await snapshot()).text;
	check('expanded: the tree', after.includes('button "More" [expanded=true]') && after.includes('StaticText "Extra"'), after);
	check('a row clicked', await click('row', 'Bob Lunch'));
	await p.waitForTimeout(300);
	check('selected: the program', (await state()).includes('row=1'), await state());
	const ax2 = (await cdp.send('Accessibility.getFullAXTree')).nodes.filter((n) => !n.ignored);
	const bob = ax2.find((n) => n.role?.value === 'row' && n.name?.value === 'Bob Lunch');
	check('selected: the tree', prop(bob, 'selected') === true);
	check('Save clicked', await click('button', 'Save'));
	await p.waitForTimeout(300);
	check('saved', (await state()).includes('saved=1'), await state());
	check('no page errors', errors.length === 0, errors.join(' | '));
} catch (e) {
	failed++;
	console.log('web-access.mjs: FAIL: ' + e.message);
}
console.log(`web-access.mjs: ${checks} checks` + (failed ? `, ${failed} FAILED` : ', ok'));
await browser.close();
server.close();
process.exit(failed ? 1 : 0);
