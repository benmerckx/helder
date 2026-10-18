// The DOM's widgets (hxmc.web.widgets) in headless Chromium (make
// web-widgets): the gallery (examples/WidgetGallery.hx, its page linking
// the theme's CSS) driven as a user would, by the pointer and the keys,
// each widget's behaviour checked through what it shows and its ARIA
// state: tabs and radio buttons roving, a select opened, moved through,
// chosen, the focus back on it; a menu's item opening a modal dialog,
// Escape closing it; a menu bar's Right; a slider's keys; a combobox
// filtering and choosing; a tooltip after its delay; a context menu; a
// list box's Shift; a tree opened by the keys; a stacked chart; a toolbar; a tag input; a toast; text fields
// typed, a number field's keys and buttons; right to left. The theme's CSS
// scoped (shadcn-scoped.css, Css.sheet's scope .hxmc): the counter in a
// page of its own styles, the page left as it is, the counter as in its own.
// Then the sizes of the counter, the form and the gallery, raw and gzipped,
// and the share of the neutral elements' realiser (hxmc.web's Neutral,
// NeutralEvent, ElementPart: what single-source widgets cost a page).
//   node packages/web/test/widgets.mjs <dir: gallery.html, *.js, shadcn.css, shadcn-scoped.css>
import { createServer } from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { gzipSync } from 'node:zlib';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const [dir] = process.argv.slice(2);
if (!dir) {
	console.error('usage: node widgets.mjs <dir>');
	process.exit(2);
}
const types = { '.js': 'text/javascript', '.css': 'text/css', '.html': 'text/html' };
const server = createServer((req, res) => {
	const p = new URL(req.url, 'http://x').pathname;
	try {
		const b = fs.readFileSync(path.join(dir, path.basename(p)));
		res.writeHead(200, { 'content-type': types[path.extname(p)] ?? 'text/html' });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
});
await new Promise(r => server.listen(0, r));
const browser = await pw.chromium.launch();
const page = await browser.newPage({ viewport: { width: 900, height: 800 } });
const errors = [];
page.on('pageerror', e => errors.push(e.message));
await page.goto(`http://localhost:${server.address().port}/gallery.html`);
let checks = 0;
const failed = [];
async function check(what, ok) {
	checks++;
	if (!(await ok)) failed.push(what);
}
const text = sel => page.locator(sel).first().textContent();
const attr = (sel, a) => page.locator(sel).first().getAttribute(a);
const focused = () => page.evaluate(() => document.activeElement?.textContent ?? '');
const press = k => page.keyboard.press(k);

// tabs: Right selects and focuses the next
await page.locator('[role=tab]').first().focus();
await press('ArrowRight');
await check('tabs: Right selects the next', (await attr('[role=tab] >> nth=1', 'aria-selected')) === 'true' && (await focused()) === 'Details');
await check('tabs: one Tab stop', (await attr('[role=tab] >> nth=0', 'tabindex')) === '-1');
// radio: a click checks, Down moves and wraps
await page.locator('label', { hasText: 'Large' }).click();
await check('radio: a click on the label', (await text('#size-shown')).includes('Large'));
await page.locator('[role=radio][aria-checked=true]').first().focus();
await press('ArrowDown');
await check('radio: Down wraps', (await text('#size-shown')).includes('Small'));
// select: opened, moved through, chosen, the focus back on it
await page.locator('[data-slot=select-trigger]').click();
await check('select: open in the top layer', page.evaluate(() => !!document.querySelector('[data-popup]:popover-open [role=listbox]')));
await check('select: the chosen option focused', (await focused()) === 'Apple');
await press('ArrowDown');
await press('Enter');
await check('select: Enter chooses', (await text('[data-slot=select-value]')) === 'Pear');
await check('select: closed, the focus back', (await page.locator('[role=listbox][data-slot=select-content]').count()) === 0
	&& (await page.evaluate(() => document.activeElement.getAttribute('data-slot'))) === 'select-trigger');
// a menu's item opening a modal dialog; Escape closes it
await page.locator('#file').click();
await check('menu: the first item focused', (await focused()) === 'New');
await press('ArrowDown');
await press('ArrowDown');
await press('Enter');
await check('menu: Rename opens the dialog', page.evaluate(() => !!document.querySelector('dialog[data-modal][open] [role=dialog]')));
await check('dialog: the focus in it', page.evaluate(() => document.activeElement.closest('dialog') != null));
await press('Escape');
await check('dialog: Escape closes it', (await page.locator('dialog[data-modal]').count()) === 0);
// menu bar: Right from an open menu opens the next
await page.locator('[data-slot=menubar-trigger]').first().click();
await press('ArrowRight');
await check('menubar: Right opens the next menu', (await attr('[data-slot=menubar-trigger] >> nth=1', 'aria-expanded')) === 'true');
await press('Escape');
// slider: Right a step
await page.locator('#volume[role=slider]').focus();
await press('ArrowRight');
await check('slider: Right a step', (await text('#volume-shown')) === '45%');
await press('Home');
await check('slider: Home', (await text('#volume-shown')) === '0%');
// checkbox
await page.locator('#check').click();
await check('checkbox: a click', (await text('#toggles')).startsWith('unchecked'));
// combobox: typing filters, Down and Enter choose, a toast says so
await page.locator('#city').fill('Ber');
await check('combobox: filtered', (await page.locator('[data-popup] [data-slot=command-item]').count()) === 2);
await page.locator('#city').press('ArrowDown');
await page.locator('#city').press('Enter');
await check('combobox: chosen', (await page.locator('#city').inputValue()) === 'Berlin');
await check('toast: shown', page.locator('[data-slot=toast]', { hasText: 'Chose Berlin' }).isVisible());
// tooltip after its delay
await page.locator('[data-slot=tooltip-trigger] button').hover();
await page.waitForTimeout(700);
await check('tooltip: shown', page.locator('[role=tooltip]').isVisible());
await page.mouse.move(0, 0);
await check('tooltip: hidden', (await page.locator('[role=tooltip]').count()) === 0);
// context menu at the pointer; Escape
await page.locator('#area').click({ button: 'right' });
await check('context menu: open', page.locator('[data-slot=context-menu-content]').isVisible());
await press('Escape');
await check('context menu: Escape', (await page.locator('[data-slot=context-menu-content]').count()) === 0);
// list box: Shift+Down extends
await page.locator('#days [role=option][tabindex="0"]').focus();
await press('Shift+ArrowDown');
await check('listbox: Shift extends', (await text('#size-shown')).endsWith('Tue Wed'));
// tree: Down selects, Right opens
await page.locator('#files').focus();
await press('ArrowDown');
await press('ArrowRight');
await check('tree: Right opens', (await page.locator('#files [role=treeitem]').count()) === 5);
// progress: not known, a bar sliding across (animation frames)
const slide = () => page.evaluate(() => document.querySelector('#loading [data-state=indeterminate]')?.style.left ?? '');
const at = await slide();
await page.waitForTimeout(200);
await check('progress: not known, sliding', at !== '' && (await slide()) !== at && (await attr('#loading', 'aria-valuenow')) === null);
// a toolbar: one Tab stop, the first; Right moves the focus and the stop, End to the last, a click makes the clicked one the stop
const stops = () => page.evaluate(() => [...document.querySelectorAll("#buttons button")].map(b => b.getAttribute("tabindex")).join(","));
const firstStops = await stops();
await page.locator("#buttons button").first().focus();
await press("ArrowRight");
const second = await page.evaluate(() => document.activeElement === document.querySelectorAll("#buttons button")[1]);
const moved = await stops();
await press("End");
const last = await page.evaluate(() => { const b = document.querySelectorAll("#buttons button"); return document.activeElement === b[b.length - 1]; });
await check("toolbar: one stop, Right and End move it", firstStops.startsWith("0,-1") && second && moved.startsWith("-1,0") && last);
// a tag input: Enter and a comma add (once), Backspace in an empty field takes the last off, a chip's × too
const chips = () => page.evaluate(() => [...document.querySelectorAll("#labels [role=listitem]")].map(li => li.firstChild.textContent).join(","));
const start = await chips();
await page.locator("#labels input").click();
await page.keyboard.type("alpha");
await press("Enter");
await page.keyboard.type("beta,alpha,");
const added = await chips();
await press("Backspace");
const less = await chips();
await page.locator("#labels [aria-label=\"Remove alpha\"]").click();
const removed = await chips();
await check("tag input: added, taken off", added === [start, "alpha", "beta"].filter(x => x).join(",") && less === [start, "alpha"].filter(x => x).join(",") && removed === start);
// a stacked bar chart: a category's bars one on another, on a scale to their greatest sum (200)
const bars = await page.evaluate(() => [...document.querySelectorAll('#visits [data-slot=chart-bar]')].map(b => { const r = b.getBoundingClientRect(); return [r.top, r.bottom, r.height]; }));
await check('chart: stacked bars', bars.length === 4 && bars[2][2] === 45 && bars[3][2] === 10 && Math.abs(bars[3][1] - bars[2][0]) < 0.5);
// text fields (<field>): typed, the signal follows; a number field's keys and buttons
await page.locator('#name').fill('');
await page.locator('#name').pressSequentially('Ada');
await check('input: typed, the signal follows', (await text('#greeting')) === 'Hello, Ada!');
await page.locator('#notes').pressSequentially('a');
await press('Enter');
await page.keyboard.type('b');
await check('textarea: typed, two lines', (await text('#lines')) === '2 lines');
const count = async () => Number(await page.locator('#count').inputValue());
const before = await count();
await page.locator('#count').focus();
await press('ArrowUp');
await press('ArrowUp');
await page.locator('[data-slot=number-field-decrement]').click();
await check('number field: Up and its button step it', (await count()) === before + 1 && (await attr('#count', 'aria-valuenow')) === String(before + 1));
// right to left
await page.locator('#rtl').click();
await check('right to left', (await page.evaluate(() => document.documentElement.dir)) === 'rtl');
// the scoped CSS: the counter's markup inside .hxmc in a page with its own headings and paragraphs
const looks = (sel) => page.evaluate((s) => {
	const c = getComputedStyle(document.querySelector(s));
	return [c.backgroundColor, c.color, c.borderRadius, c.height, c.paddingLeft, c.fontSize, c.fontFamily, c.boxSizing].join(' ');
}, sel);
await page.goto(`http://localhost:${server.address().port}/counter.html`);
const own = await looks('[data-slot=button]'), paper = await page.evaluate(() => getComputedStyle(document.body).backgroundColor), markup = await page.evaluate(() => document.body.innerHTML.replace(/<script[^]*?<\/script>/g, ''));
fs.writeFileSync(path.join(dir, 'scoped.html'), '<!doctype html><html lang="en"><head><meta charset="utf-8"><link rel="stylesheet" href="shadcn-scoped.css"></head>'
	+ '<body><h2 id="site">The site</h2><p id="para">Its own text</p><div class="hxmc" id="demo">' + markup + '</div></body></html>\n');
await page.goto(`http://localhost:${server.address().port}/scoped.html`);
await check('scoped: the page outside as it is', page.evaluate(() => getComputedStyle(document.getElementById('site')).fontSize === '24px'
	&& getComputedStyle(document.getElementById('para')).marginTop === '16px' && getComputedStyle(document.body).backgroundColor === 'rgba(0, 0, 0, 0)'
	&& getComputedStyle(document.body).boxSizing === 'content-box'));
await check('scoped: the counter as in its own page', (await looks('#demo [data-slot=button]')) === own);
await check('scoped: the scope in the page\'s colours', (await page.evaluate(() => getComputedStyle(document.getElementById('demo')).backgroundColor)) === paper && paper !== 'rgba(0, 0, 0, 0)');
await browser.close();
server.close();
for (const e of errors) failed.push('page error: ' + e);
for (const f of failed) console.log('widgets: FAILED ' + f);
console.log(`widgets: ${checks} checks` + (failed.length ? `, ${failed.length} FAILED` : ', ok'));
// (the bytes of a bundle's classes of these names: each class to its closing brace)
function share(src, names) {
	let n = 0;
	for (const m of src.matchAll(/class (hxmc_web_\w+|hxmc_web__\$\w+)[^{]*\{/g)) {
		if (!names.some((x) => m[1].includes(x))) continue;
		let d = 0, k = m.index + m[0].length - 1;
		for (; k < src.length; k++) if (src[k] === '{') d++; else if (src[k] === '}' && --d === 0) break;
		n += k + 1 - m.index;
	}
	return n;
}
for (const f of ['counter.js', 'form.js', 'gallery.js', 'shadcn.css', 'shadcn-scoped.css']) {
	const b = fs.readFileSync(path.join(dir, f));
	const realiser = f.endsWith('.js') ? share(b.toString(), ['Neutral', 'ElementPart']) : 0;
	console.log(`widgets: ${f} ${(b.length / 1024).toFixed(1)} KB, ${(gzipSync(b, { level: 9 }).length / 1024).toFixed(1)} KB gzipped`
		+ (f.endsWith('.js') ? `, the neutral realiser ${(realiser / 1024).toFixed(1)} KB` : ''));
}
process.exit(failed.length ? 1 : 0);
