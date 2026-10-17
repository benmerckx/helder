// Writes packages/ui/test/boxes.png: Chromium drawing boxes.json's boxes
// (absolutely placed, border-box; each corner's radius and each side's
// border width as CSS writes them, one value or several; overflow hidden
// clipping to the padding box's rounded corners; CSS transforms about their
// origins, nested ones inside their parents') on white: what BoxTest's
// renderer must draw (make ui-draw-check).
//   node packages/ui/test/box-ref.mjs   (needs Playwright)
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const W = 320, H = 240;
const boxes = JSON.parse(fs.readFileSync(path.join(here, 'boxes.json'), 'utf8'));
const px = v => String(v).split(' ').map(x => x + 'px').join(' ');
const html = b => `<div style="position:absolute;box-sizing:border-box;left:${b.left}px;top:${b.top}px;width:${b.width}px;height:${b.height}px;`
	+ `background:${b.background};border-radius:${px(b.radius ?? 0)};${b.border != null ? `border-style:solid;border-width:${px(b.border)};border-color:${b.borderColor};` : ''}`
	+ `${b.overflow ? `overflow:${b.overflow};` : ''}${b.transform ? `transform:${b.transform};` : ''}${b.origin ? `transform-origin:${b.origin};` : ''}">${(b.children ?? []).map(html).join('')}</div>`;
const browser = await pw.chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
await page.setContent(`<body style="margin:0;background:#fff">${boxes.map(html).join('')}</body>`);
await page.screenshot({ path: path.join(here, 'boxes.png'), clip: { x: 0, y: 0, width: W, height: H } });
await browser.close();
console.log('box-ref: boxes.png');
