// Writes packages/ui/test/css/: CSS colours as Chromium computes them
// (colors.json: the text and its RGBA), and CSS gradients as Chromium draws
// them as a box's background (<case>.png, RGBA, the box's size;
// gradients.json: names, the CSS and sizes), which UiTest compares with
// Color.parse and Gradient.render (make ui-check).
//   node packages/ui/test/css-cases.mjs   (needs Playwright)
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(here, 'css');
fs.mkdirSync(out, { recursive: true });

const colors = ['#f00', '#0f08', '#336699', '#33669980', 'ABCDEF', 'tomato', 'RebeccaPurple', 'transparent', 'rgb(10, 20, 30)', 'rgb(10 20 30 / 50%)',
	'rgba(255,0,0,0.25)', 'rgb(100%, 50%, 0%)', 'rgb(300, -5, 128)', 'hsl(120, 100%, 25%)', 'hsl(210deg 60% 70%)', 'hsla(0, 0%, 50%, 0.5)',
	'hsl(-30, 80%, 40%)', 'hsl(400, 50%, 50%)'];

// [name, css, width, height]
const gradients = [
	['linear-default', 'linear-gradient(#ef4444, #3b82f6)', 40, 30],
	['linear-to-right', 'linear-gradient(to right, #000, #fff)', 60, 20],
	['linear-angle', 'linear-gradient(45deg, #f59e0b, #10b981 60%, #6366f1)', 50, 40],
	['linear-turn', 'linear-gradient(0.3turn, red, blue)', 40, 40],
	['linear-corner', 'linear-gradient(to top right, #fde047, #be123c)', 64, 24],
	['linear-stops', 'linear-gradient(90deg, red 10px, yellow, lime 50%, blue 80%, purple)', 64, 16],
	['linear-hard', 'linear-gradient(to bottom, #0ea5e9 50%, #f97316 50%)', 30, 40],
	['linear-two-positions', 'linear-gradient(to right, red 0 20%, green 20% 60%, blue 60%)', 50, 10],
	['linear-alpha', 'linear-gradient(to right, rgba(255, 0, 0, 1), rgba(0, 0, 255, 0))', 60, 12],
	['linear-transparent', 'linear-gradient(to right, transparent, #16a34a)', 60, 12],
	['repeating-linear', 'repeating-linear-gradient(45deg, #1e293b 0 6px, #e2e8f0 6px 12px)', 48, 48],
	['radial-default', 'radial-gradient(#fff, #7c3aed)', 60, 40],
	['radial-circle', 'radial-gradient(circle, #fde047, #ea580c 70%, #7f1d1d)', 48, 48],
	['radial-closest-side', 'radial-gradient(closest-side, #22c55e, #064e3b)', 60, 30],
	['radial-at', 'radial-gradient(circle at 20% 30%, white, #0369a1)', 64, 40],
	['radial-farthest-side', 'radial-gradient(farthest-side at left top, #f472b6, #4c1d95)', 40, 40],
	['radial-size', 'radial-gradient(circle 20px at center, #facc15, #1e3a8a)', 60, 40],
	['radial-ellipse-size', 'radial-gradient(30px 10px, #fff 0, #111 100%)', 60, 40],
	['repeating-radial', 'repeating-radial-gradient(circle, #f43f5e 0 4px, #fff1f2 4px 8px)', 48, 48],
];

const browser = await pw.chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 1 });
const colorList = await page.evaluate((colors) => {
	const d = document.createElement('div');
	document.body.append(d);
	return colors.map((c) => {
		d.style.color = '';
		d.style.color = c.startsWith('#') || !/^[0-9A-Fa-f]{3,8}$/.test(c) ? c : '#' + c;
		const m = getComputedStyle(d).color.match(/[\d.]+/g).map(Number);
		return { css: c, rgba: [m[0], m[1], m[2], Math.round((m.length > 3 ? m[3] : 1) * 255)] };
	});
}, colors);
fs.writeFileSync(path.join(out, 'colors.json'), JSON.stringify(colorList, null, '\t') + '\n');

const list = [];
for (const [name, css, w, h] of gradients) {
	await page.setContent(`<html style="background:transparent"><body style="margin:0;background:transparent"><div id="b" style="width:${w}px;height:${h}px;background:${css}"></div></body></html>`);
	const shot = await page.locator('#b').screenshot({ omitBackground: true, type: 'png' });
	fs.writeFileSync(path.join(out, name + '.png'), shot);
	list.push({ name, css, width: w, height: h });
}
fs.writeFileSync(path.join(out, 'gradients.json'), JSON.stringify(list, null, '\t') + '\n');
console.log(`css-cases.mjs: ${colorList.length} colours, ${list.length} gradients (chromium ${browser.version()})`);
await browser.close();
