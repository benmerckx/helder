// Writes packages/ui/test/transform.png: Chromium drawing transforms.json's
// boxes (absolutely placed, border-box, CSS transforms about their origins,
// nested ones inside their parents' transforms) on white: what TransformTest's
// renderer must draw (make ui-draw-check).
//   node packages/ui/test/transform-ref.mjs   (needs Playwright)
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const W = 240, H = 160;
const boxes = JSON.parse(fs.readFileSync(path.join(here, 'transforms.json'), 'utf8'));
const html = b => `<div style="position:absolute;box-sizing:border-box;left:${b.left}px;top:${b.top}px;width:${b.width}px;height:${b.height}px;`
	+ `background:${b.background};border-radius:${b.radius ?? 0}px;${b.border ? `border:${b.border}px solid ${b.borderColor};` : ''}`
	+ `transform:${b.transform};${b.origin ? `transform-origin:${b.origin};` : ''}">${(b.children ?? []).map(html).join('')}</div>`;
const browser = await pw.chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
await page.setContent(`<body style="margin:0;background:#fff">${boxes.map(html).join('')}</body>`);
await page.screenshot({ path: path.join(here, 'transform.png'), clip: { x: 0, y: 0, width: W, height: H } });
await browser.close();
console.log('transform-ref: transform.png');
