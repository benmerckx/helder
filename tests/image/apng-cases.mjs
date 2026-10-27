// Writes tests/image/apng/: animated PNGs (APNG) and every frame as
// Chromium's ImageDecoder composes them (<case>.frames.rgba; RGBA8), with
// their durations and repetitions (cases.json), which PngDecoder.frames
// must give exactly; their default images as libpng decodes them
// (<case>.rgba, through ImageMagick), Image.decode's. Two are written here chunk by chunk, to
// have each way of drawing a frame (replacing or over what is there; then
// left, cleared or put back) and a default image apart from the animation;
// one by ffmpeg's encoder (its own regions and ops). Alphas are 0 or 255,
// where every compositor agrees, transparent pixels black.
// ImageTest decodes them (bun run test image).
//   node tests/image/apng-cases.mjs   (needs ffmpeg, ImageMagick and Playwright's Chromium)
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(here, 'apng');
const tmp = fs.mkdtempSync(path.join(process.env.TMPDIR ?? '/tmp', 'apng-cases-'));
fs.mkdirSync(out, { recursive: true });

function crc32(b) {
	let r = 0xffffffff;
	for (const x of b) {
		r ^= x;
		for (let k = 0; k < 8; k++) r = r & 1 ? 0xedb88320 ^ (r >>> 1) : r >>> 1;
	}
	return (r ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
	const h = Buffer.alloc(8);
	h.writeUInt32BE(data.length, 0);
	h.write(type, 4, 'latin1');
	const c = Buffer.alloc(4);
	c.writeUInt32BE(crc32(Buffer.concat([Buffer.from(type, 'latin1'), data])), 0);
	return Buffer.concat([h, data, c]);
}
// an RGBA8 image (w, h, fill(x, y) -> [r, g, b, a]) as zlib'd rows (filter: row y % 5 alternating none and sub)
function image(w, h, fill) {
	const rows = [];
	for (let y = 0; y < h; y++) {
		const row = Buffer.alloc(1 + 4 * w), f = y % 2;
		row[0] = f;
		const raw = Buffer.alloc(4 * w);
		for (let x = 0; x < w; x++) raw.set(fill(x, y), 4 * x);
		for (let i = 0; i < raw.length; i++) row[1 + i] = (raw[i] - (f == 1 && i >= 4 ? raw[i - 4] : 0)) & 0xff;
		rows.push(row);
	}
	return zlib.deflateSync(Buffer.concat(rows));
}
// a frame: region (w, h at x, y), delay num / den, dispose (0 none, 1 background, 2 previous), blend (0 source, 1 over)
function fctl(seq, f) {
	const b = Buffer.alloc(26);
	b.writeUInt32BE(seq, 0);
	b.writeUInt32BE(f.w, 4);
	b.writeUInt32BE(f.h, 8);
	b.writeUInt32BE(f.x, 12);
	b.writeUInt32BE(f.y, 16);
	b.writeUInt16BE(f.num, 20);
	b.writeUInt16BE(f.den, 22);
	b[24] = f.dispose;
	b[25] = f.blend;
	return chunk('fcTL', b);
}
// an APNG: frames (the first in IDAT unless a separate default image is given), plays
function apng(w, h, frames, plays, defaultImage) {
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(w, 0);
	ihdr.writeUInt32BE(h, 4);
	ihdr[8] = 8;
	ihdr[9] = 6;
	const actl = Buffer.alloc(8);
	actl.writeUInt32BE(frames.length, 0);
	actl.writeUInt32BE(plays, 4);
	const parts = [Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('acTL', actl)];
	let seq = 0;
	if (defaultImage) parts.push(chunk('IDAT', image(w, h, defaultImage)));
	frames.forEach((f, i) => {
		parts.push(fctl(seq++, f));
		const data = image(f.w, f.h, f.fill);
		if (i == 0 && !defaultImage) parts.push(chunk('IDAT', data));
		else {
			// (split in two fdATs)
			const half = data.length >> 1;
			for (const piece of [data.subarray(0, half), data.subarray(half)]) {
				const s = Buffer.alloc(4);
				s.writeUInt32BE(seq++, 0);
				parts.push(chunk('fdAT', Buffer.concat([s, piece])));
			}
		}
	});
	parts.push(chunk('IEND', Buffer.alloc(0)));
	return Buffer.concat(parts);
}

const files = [];
function add(name, file) {
	const p = path.join(out, name + '.png');
	fs.writeFileSync(p, file);
	fs.writeFileSync(path.join(out, name + '.rgba'), execFileSync('convert', ['png:' + p, '-depth', '8', 'rgba:-']));
	files.push([name, p]);
}

const grad = (x, y) => [x * 15, y * 20, 128, 255];
const ops = [
	{ x: 0, y: 0, w: 16, h: 12, num: 1, den: 10, dispose: 0, blend: 0, fill: grad },
	// (over: its holes show the first frame; then cleared)
	{ x: 3, y: 2, w: 6, h: 5, num: 5, den: 100, dispose: 1, blend: 1, fill: (x, y) => ((x + y) % 3 == 0 ? [0, 0, 0, 0] : [230, 20, 40, 255]) },
	// (replacing: its holes clear; then put back)
	{ x: 5, y: 4, w: 8, h: 6, num: 0, den: 0, dispose: 2, blend: 0, fill: (x, y) => (x == 0 ? [0, 0, 0, 0] : [20, 60, 230, 255]) },
	{ x: 0, y: 0, w: 4, h: 4, num: 30, den: 100, dispose: 0, blend: 1, fill: (x, y) => (x < 2 ? [0, 0, 0, 0] : [10, 200, 90, 255]) }
];
add('ops', apng(16, 12, ops, 3));
// (a default image not in the animation; the first frame's "previous" a clear; forever)
add('apart', apng(10, 8, [
	{ x: 2, y: 2, w: 5, h: 4, num: 1, den: 4, dispose: 2, blend: 0, fill: () => [250, 200, 0, 255] },
	{ x: 0, y: 0, w: 10, h: 8, num: 1, den: 2, dispose: 0, blend: 1, fill: (x, y) => (y < 4 ? [0, 0, 0, 0] : [90, 90, 90, 255]) }
], 0, (x, y) => [200, 0, 200, 255]));

// ffmpeg's encoder: three opaque frames, a moving square, twice
{
	const f = [0, 1, 2].map((i) => path.join(tmp, `f${i}.png`));
	f.forEach((p, i) => execFileSync('convert', ['-size', '24x16', 'xc:#3366ff', '-fill', '#e01030', '-draw', `rectangle ${3 + 6 * i},4 ${8 + 6 * i},10`, p]));
	const p = path.join(tmp, 'enc.png');
	execFileSync('ffmpeg', ['-v', 'error', '-framerate', '5', '-i', path.join(tmp, 'f%d.png'), '-plays', '2', '-f', 'apng', p]);
	add('encoded', fs.readFileSync(p));
}

// Chromium's frames (ImageDecoder: a secure context, a page at localhost)
const browser = await pw.chromium.launch();
const page = await browser.newPage();
await page.route('http://localhost/', (r) => r.fulfill({ contentType: 'text/html', body: '<!doctype html>' }));
await page.goto('http://localhost/');
const cases = [];
for (const [name, file] of files) {
	const r = await page.evaluate(async (b64) => {
		const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
		const dec = new ImageDecoder({ data: bytes, type: 'image/png' });
		await dec.tracks.ready;
		const t = dec.tracks.selectedTrack, frames = [], data = [];
		let w = 0, h = 0;
		for (let i = 0; i < t.frameCount; i++) {
			const { image } = await dec.decode({ frameIndex: i });
			w = image.displayWidth;
			h = image.displayHeight;
			const c = new OffscreenCanvas(w, h), g = c.getContext('2d');
			g.drawImage(image, 0, 0);
			data.push(...g.getImageData(0, 0, w, h).data);
			frames.push(image.duration / 1e6);
			image.close();
		}
		return { w, h, frames, repetition: t.repetitionCount === Infinity ? -1 : t.repetitionCount, data };
	}, fs.readFileSync(file).toString('base64'));
	const frames = Buffer.from(r.data);
	// (transparent pixels black: their colours are not drawn)
	for (let i = 0; i < frames.length; i += 4) if (frames[i + 3] == 0) frames.fill(0, i, i + 4);
	fs.writeFileSync(path.join(out, name + '.frames.rgba'), frames);
	cases.push({ name, width: r.w, height: r.h, durations: r.frames, repetition: r.repetition });
}
await browser.close();
fs.writeFileSync(path.join(out, 'cases.json'), JSON.stringify(cases, null, '\t') + '\n');
fs.rmSync(tmp, { recursive: true });
console.log(`apng-cases.mjs: ${cases.length} cases in ${out} (chromium ${browser.version()})`);
