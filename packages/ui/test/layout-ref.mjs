// The layout tests' reference: each case of layout-cases.mjs drawn by
// Chromium's flexbox (with the CSS that sets hxmc.ui's defaults: border-box,
// column, position relative), its boxes read back, each
// edge rounded as hxmc.ui.Layout rounds them, into layout-expected.json,
// which UiTest compares with (make ui-check). Run it after changing the
// cases (Playwright from npm, with Chromium):
//   node packages/ui/test/layout-ref.mjs
import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { cases } from './layout-cases.mjs';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));

const px = (v) => (typeof v === 'number' ? v + 'px' : v);
const KEBAB = { direction: 'flex-direction', wrap: 'flex-wrap', justify: 'justify-content', alignItems: 'align-items', alignSelf: 'align-self',
	alignContent: 'align-content', grow: 'flex-grow', shrink: 'flex-shrink', basis: 'flex-basis', minWidth: 'min-width', minHeight: 'min-height',
	maxWidth: 'max-width', maxHeight: 'max-height', rowGap: 'row-gap', columnGap: 'column-gap', borderWidth: 'border-width', aspectRatio: 'aspect-ratio',
	gridTemplateColumns: 'grid-template-columns', gridTemplateRows: 'grid-template-rows', gridAutoColumns: 'grid-auto-columns', gridAutoRows: 'grid-auto-rows',
	gridAutoFlow: 'grid-auto-flow', gridColumn: 'grid-column', gridRow: 'grid-row', gridArea: 'grid-area', gridTemplateAreas: 'grid-template-areas', justifyItems: 'justify-items', justifySelf: 'justify-self', dir: 'direction' };
const VALUES = { Row: 'row', Column: 'column', RowReverse: 'row-reverse', ColumnReverse: 'column-reverse', Start: 'flex-start', End: 'flex-end',
	Center: 'center', Stretch: 'stretch', SpaceBetween: 'space-between', SpaceAround: 'space-around', SpaceEvenly: 'space-evenly', Auto: 'auto',
	Absolute: 'absolute', Relative: 'relative', None: 'none', Flex: 'flex', Grid: 'grid', Visible: 'visible', Hidden: 'hidden', Scroll: 'scroll',
	Rtl: 'rtl', Ltr: 'ltr' };

function css(style) {
	// (a grid: CSS's normal track alignment, auto tracks stretched, where the page's rule says flex-start)
	let s = style?.display === 'Grid' && style.alignContent === undefined ? 'align-content:normal;' : '';
	for (const [k, v] of Object.entries(style ?? {})) {
		const name = KEBAB[k] ?? k;
		let value;
		if (k === 'wrap') value = v ? 'wrap' : 'nowrap';
		else if (k === 'grow' || k === 'shrink' || k === 'aspectRatio' || k === 'order') value = String(v);
		else if (k === 'padding' || k === 'margin') value = (Array.isArray(v) ? v : [v]).map(px).join(' ');
		else if (k === 'borders') { s += 'border-style:solid;border-width:' + v.map(px).join(' ') + ';'; continue; }
		else if (k === 'alignContent' && v === 'Start') value = 'flex-start';
		else value = VALUES[v] ?? px(v);
		s += `${name}:${value};`;
	}
	return s;
}

function html(node) {
	return `<div style="${css(node.style)}">${(node.children ?? []).map(html).join('')}</div>`;
}

const page = `<!doctype html><style>
body { margin: 0 }
div { display: flex; flex-direction: column; box-sizing: border-box; position: relative; border-style: solid; border-width: 0; flex-shrink: 1; align-content: flex-start }
#root > div { position: absolute; left: 0; top: 0 }
</style><div id="root"></div>`;

const browser = await pw.chromium.launch();
const p = await browser.newPage({ viewport: { width: 1200, height: 900 } });
await p.setContent(page);
const expected = {};
for (const c of cases) {
	// (the root is the viewport: its size given)
	const tree = { ...c.tree, style: { ...c.tree.style, width: c.width, height: c.height } };
	expected[c.name] = await p.evaluate((h) => {
		const root = document.getElementById('root');
		root.innerHTML = h;
		const boxes = [];
		const r0 = root.firstChild.getBoundingClientRect();
		(function walk(e) {
			const r = e.getBoundingClientRect();
			const x0 = Math.round(r.left - r0.left), y0 = Math.round(r.top - r0.top), x1 = Math.round(r.right - r0.left), y1 = Math.round(r.bottom - r0.top);
			boxes.push(e.style.display === 'none' ? [0, 0, 0, 0] : [x0, y0, x1 - x0, y1 - y0]);
			for (const ch of e.children) walk(ch);
		})(root.firstChild);
		return boxes;
	}, html(tree));
}
await browser.close();
await writeFile(path.join(here, 'layout-cases.json'), JSON.stringify(cases, null, '\t') + '\n');
await writeFile(path.join(here, 'layout-expected.json'), JSON.stringify(expected, null, '\t').replace(/\[\s+(-?\d+),\s+(-?\d+),\s+(-?\d+),\s+(-?\d+)\s+\]/g, '[$1, $2, $3, $4]') + '\n');
console.log(`layout-ref.mjs: ${cases.length} cases (chromium ${browser.version()})`);
