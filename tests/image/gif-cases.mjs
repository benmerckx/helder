// Writes tests/image/gif/: GIF files of the kinds GifDecoder reads (a
// dithered 256-colour palette, 4 colours, black and white, interlaced, a
// transparent colour, a frame smaller than the screen at an offset, an
// animation's first frame), each with the RGBA8 pixels Chromium decodes from
// it (<case>.rgba; cases.json: names and sizes), which GifDecoder must give
// exactly; and animations (frames at offsets, each disposal method,
// transparency, a delay of 0), each frame as Chromium's ImageDecoder
// composes it (<case>.frames.rgba, one after the other; cases.json: their
// durations and the repetition count). ImageMagick (convert) encodes them.
// ImageTest decodes them (bun run test image).
//   node tests/image/gif-cases.mjs   (needs ImageMagick and Playwright)
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
const out = path.join(here, 'gif');
fs.mkdirSync(out, { recursive: true });

// a source image: gradients, hard edges, saturated colours
function source(w, h) {
	const px = Buffer.alloc(w * h * 3);
	for (let y = 0; y < h; y++)
		for (let x = 0; x < w; x++) {
			const o = 3 * (y * w + x);
			let r = (x * 255) / Math.max(1, w - 1), g = (y * 255) / Math.max(1, h - 1), b = 128 + 127 * Math.sin((x + y) / 3);
			if ((x >> 2) % 3 === 0 && y > h / 2) [r, g, b] = [230, 20, 40];
			if (x > w * 0.7 && y < h * 0.3) [r, g, b] = [10, 200, 90];
			px[o] = r;
			px[o + 1] = g;
			px[o + 2] = b;
		}
	return px;
}
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
function png(px, w, h) {
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(w, 0);
	ihdr.writeUInt32BE(h, 4);
	ihdr[8] = 8;
	ihdr[9] = 2;
	const raw = Buffer.alloc((3 * w + 1) * h);
	for (let y = 0; y < h; y++) px.copy(raw, y * (3 * w + 1) + 1, 3 * y * w, 3 * (y + 1) * w);
	return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

const tmp = fs.mkdtempSync(path.join(out, '.src-'));
const src = path.join(tmp, 'src.png');
fs.writeFileSync(src, png(source(37, 29), 37, 29));
// (small frames: a solid red, a solid blue square)
const solid = (name, r, g, b) => {
	const f = path.join(tmp, name + '.png'), w = 12, h = 10, px = Buffer.alloc(w * h * 3);
	for (let i = 0; i < w * h; i++) [px[3 * i], px[3 * i + 1], px[3 * i + 2]] = [r, g, b];
	fs.writeFileSync(f, png(px, w, h));
	return f;
};
const red = solid('red', 220, 30, 30), blue = solid('blue', 30, 60, 220);
const cases = [
	['dither-256', [src]],
	['colors-4', [src, '+dither', '-colors', '4']],
	['monochrome', [src, '-monochrome']],
	['interlaced', [src, '-interlace', 'GIF']],
	['transparent', [src, '+dither', '-colors', '32', '-transparent', 'rgb(230,20,40)']],
	['offset-frame', [src, '-set', 'page', '50x40+6+4']],
	['animation', [src, '(', src, '-negate', ')', '-delay', '10', '-loop', '0']],
	['large', ['-size', '160x120', 'plasma:fractal', '-seed', '1']],
];
// animations: the frames composed (each disposal method; transparency over the frame before)
const animations = [
	['anim-none', ['-delay', '20', '-dispose', 'None', src, '-page', '+5+4', red, '-page', '+14+12', blue, '-loop', '0']],
	['anim-background', ['-delay', '15', '-dispose', 'Background', src, '-page', '+5+4', red, '-page', '+14+12', blue, '-loop', '3']],
	['anim-previous', ['-delay', '10', '-dispose', 'None', src, '-dispose', 'Previous', '-page', '+5+4', red, '-dispose', 'None', '-page', '+14+12', blue]],
	['anim-transparent', ['-delay', '0', '-dispose', 'None', src, '(', src, '-negate', '+dither', '-colors', '16', '-fuzz', '30%', '-transparent', 'rgb(25,235,215)', ')', '-loop', '0']],
];
const files = [];
for (const [name, args] of cases) {
	const file = path.join(out, name + '.gif');
	execFileSync('convert', [...args, file]);
	files.push([name, file]);
}
const animated = [];
for (const [name, args] of animations) {
	const file = path.join(out, name + '.gif');
	execFileSync('convert', [...args, file]);
	animated.push([name, file]);
}
fs.rmSync(tmp, { recursive: true });

// Chromium's pixels (the first frame)
const browser = await pw.chromium.launch();
const page = await browser.newPage();
const index = [];
for (const [name, file] of files) {
	const r = await page.evaluate(async (b64) => {
		const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
		const bmp = await createImageBitmap(new Blob([bytes], { type: 'image/gif' }), { colorSpaceConversion: 'none', premultiplyAlpha: 'none' });
		const c = new OffscreenCanvas(bmp.width, bmp.height), g = c.getContext('2d');
		g.drawImage(bmp, 0, 0);
		return { w: bmp.width, h: bmp.height, data: Array.from(g.getImageData(0, 0, bmp.width, bmp.height).data) };
	}, fs.readFileSync(file).toString('base64'));
	fs.writeFileSync(path.join(out, name + '.rgba'), Buffer.from(r.data));
	index.push({ name, width: r.w, height: r.h });
}
// Chromium's frames (ImageDecoder: a secure context, a page at localhost)
await page.route('http://localhost/', (r) => r.fulfill({ contentType: 'text/html', body: '<!doctype html>' }));
await page.goto('http://localhost/');
for (const [name, file] of animated) {
	const r = await page.evaluate(async (b64) => {
		const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
		const dec = new ImageDecoder({ data: bytes, type: 'image/gif' });
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
	fs.writeFileSync(path.join(out, name + '.frames.rgba'), Buffer.from(r.data));
	index.push({ name, width: r.w, height: r.h, durations: r.frames, repetition: r.repetition });
}
await browser.close();
fs.writeFileSync(path.join(out, 'cases.json'), JSON.stringify(index, null, '\t') + '\n');
console.log(`gif-cases: ${index.length} cases (chromium ${browser.version()})`);
