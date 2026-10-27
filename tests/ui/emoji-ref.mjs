// Writes tests/ui/emoji.png: Chromium drawing colour emoji (Noto
// Color Emoji's bitmaps: a heart with VS16, a thumbs up with a skin tone,
// a flag) at 32px, left at x 10 on the baseline y 41, on white: what
// EmojiTest's renderer must draw (npm test -- ui-draw, where the font is).
//   node tests/ui/emoji-ref.mjs   (needs Playwright, Noto Color Emoji)
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
export const TEXT = '❤️\u{1F44D}\u{1F3FD}\u{1F1E7}\u{1F1EA}', W = 200, H = 64;

const browser = await pw.chromium.launch();
const page = await browser.newPage();
const px = await page.evaluate(({ TEXT, W, H }) => {
	const c = new OffscreenCanvas(W, H), g = c.getContext('2d');
	g.fillStyle = '#fff';
	g.fillRect(0, 0, W, H);
	g.font = '32px "Noto Color Emoji"';
	g.fillStyle = '#000';
	g.fillText(TEXT, 10, 41);
	return Array.from(g.getImageData(0, 0, W, H).data);
}, { TEXT, W, H });
await browser.close();
// (a PNG: RGBA8, filter 0 rows)
function crc32(b) {
	let r = 0xffffffff;
	for (const x of b) {
		r ^= x;
		for (let k = 0; k < 8; k++) r = r & 1 ? 0xedb88320 ^ (r >>> 1) : r >>> 1;
	}
	return (r ^ 0xffffffff) >>> 0;
}
const chunk = (type, data) => {
	const h = Buffer.alloc(8), c = Buffer.alloc(4);
	h.writeUInt32BE(data.length, 0);
	h.write(type, 4, 'latin1');
	c.writeUInt32BE(crc32(Buffer.concat([Buffer.from(type, 'latin1'), data])), 0);
	return Buffer.concat([h, data, c]);
};
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(W, 0);
ihdr.writeUInt32BE(H, 4);
ihdr[8] = 8;
ihdr[9] = 6;
const raw = Buffer.alloc((4 * W + 1) * H);
for (let y = 0; y < H; y++) Buffer.from(px.slice(4 * W * y, 4 * W * (y + 1))).copy(raw, y * (4 * W + 1) + 1);
fs.writeFileSync(path.join(here, 'emoji.png'), Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
console.log('emoji-ref: emoji.png');
