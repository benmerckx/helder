// Writes tests/ui/jpeg/: JPEG files of the kinds JpegDecoder reads
// (sampling factors 4:4:4, 4:2:2, 4:2:0, 4:4:0, 4:1:1; greyscale; CMYK;
// progressive; restart intervals; quality 100; an EXIF orientation; odd
// sizes, a component two samples wide), each with the RGBA8 pixels
// Chromium decodes from it (<case>.rgba; cases.json: names and sizes),
// which JpegDecoder must give exactly: libjpeg-turbo's inverse DCT,
// upsampling and colour conversion, as Chromium has them. ImageMagick
// (convert) encodes most; this script the rest: restart intervals (a small
// baseline encoder below) and the orientation (an APP1 segment added).
// UiTest decodes them (npm test -- ui).
//   node tests/ui/jpeg-cases.mjs   (needs ImageMagick and Playwright)
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
const out = path.join(here, 'jpeg');
fs.mkdirSync(out, { recursive: true });

// a source image: smooth gradients, hard edges, saturated colours
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

// a baseline encoder (4:4:4 YCbCr, or greyscale) with a restart interval:
// flat Huffman tables (every DC size 4 bits, every AC symbol 8)
const ZZ = [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63];
function encode(px, w, h, restart, grey) {
	const q = Array.from({ length: 64 }, (_, i) => 4 + ((i * 7) % 13));
	const acSyms = [0x00, 0xf0];
	for (let r = 0; r < 16; r++) for (let s = 1; s <= 10; s++) acSyms.push((r << 4) | s);
	const acCode = new Map(acSyms.map((s, i) => [s, i]));
	const bytes = [];
	let acc = 0, n = 0;
	const put = (v, len) => {
		for (let i = len - 1; i >= 0; i--) {
			acc = (acc << 1) | ((v >> i) & 1);
			if (++n === 8) {
				bytes.push(acc);
				if (acc === 0xff) bytes.push(0);
				acc = n = 0;
			}
		}
	};
	const flush = () => { while (n) put(1, 1); };
	const size = (v) => (v === 0 ? 0 : 32 - Math.clz32(Math.abs(v)));
	const bitsOf = (v, s) => (v >= 0 ? v : v + (1 << s) - 1);
	const ncomp = grey ? 1 : 3;
	const plane = (c, x, y) => {
		x = Math.min(x, w - 1);
		y = Math.min(y, h - 1);
		const o = 3 * (y * w + x), R = px[o], G = px[o + 1], B = px[o + 2];
		if (c === 0) return 0.299 * R + 0.587 * G + 0.114 * B;
		if (c === 1) return -0.168736 * R - 0.331264 * G + 0.5 * B + 128;
		return 0.5 * R - 0.418688 * G - 0.081312 * B + 128;
	};
	const pred = [0, 0, 0];
	const mx = Math.ceil(w / 8), my = Math.ceil(h / 8);
	let units = 0, rst = 0;
	for (let by = 0; by < my; by++)
		for (let bx = 0; bx < mx; bx++) {
			if (restart && units > 0 && units % restart === 0) {
				flush();
				bytes.push(0xff, 0xd0 + (rst++ % 8));
				pred.fill(0);
			}
			units++;
			for (let c = 0; c < ncomp; c++) {
				const f = [];
				for (let v = 0; v < 8; v++)
					for (let u = 0; u < 8; u++) {
						let s = 0;
						for (let y = 0; y < 8; y++)
							for (let x = 0; x < 8; x++)
								s += (plane(c, bx * 8 + x, by * 8 + y) - 128) * Math.cos(((2 * x + 1) * u * Math.PI) / 16) * Math.cos(((2 * y + 1) * v * Math.PI) / 16);
						f[v * 8 + u] = (s * (u ? 1 : Math.SQRT1_2) * (v ? 1 : Math.SQRT1_2)) / 4;
					}
				const z = ZZ.map((p) => Math.round(f[p] / q[p]));
				const d = z[0] - pred[c];
				pred[c] = z[0];
				put(size(d), 4);
				put(bitsOf(d, size(d)), size(d));
				let run = 0;
				for (let k = 1; k < 64; k++) {
					if (z[k] === 0) { run++; continue; }
					while (run > 15) { put(acCode.get(0xf0), 8); run -= 16; }
					const s = size(z[k]);
					put(acCode.get((run << 4) | s), 8);
					put(bitsOf(z[k], s), s);
					run = 0;
				}
				if (run) put(acCode.get(0x00), 8);
			}
		}
	flush();
	const seg = (m, body) => [0xff, m, (body.length + 2) >> 8, (body.length + 2) & 255, ...body];
	const dqt = [0, ...ZZ.map((p) => q[p])];
	const sof = [8, h >> 8, h & 255, w >> 8, w & 255, ncomp];
	for (let c = 0; c < ncomp; c++) sof.push(c + 1, 0x11, 0);
	const dc = [0x00, 0, 0, 0, 12, ...Array(12).fill(0), ...Array.from({ length: 12 }, (_, i) => i)];
	const ac = [0x10, 0, 0, 0, 0, 0, 0, 0, acSyms.length, ...Array(8).fill(0), ...acSyms];
	const sos = [ncomp];
	for (let c = 0; c < ncomp; c++) sos.push(c + 1, 0x00);
	sos.push(0, 63, 0);
	const jfif = [0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0];
	return Buffer.from([0xff, 0xd8, ...seg(0xe0, jfif), ...seg(0xdb, dqt), ...seg(0xc0, sof), ...seg(0xc4, dc), ...seg(0xc4, ac), ...seg(0xdd, [restart >> 8, restart & 255]), ...seg(0xda, sos), ...bytes, 0xff, 0xd9]);
}

// an EXIF APP1 segment with an orientation, after SOI
function oriented(jpg, o) {
	const tiff = [0x49, 0x49, 0x2a, 0, 8, 0, 0, 0, 1, 0, 0x12, 0x01, 3, 0, 1, 0, 0, 0, o, 0, 0, 0, 0, 0, 0, 0];
	const body = [0x45, 0x78, 0x69, 0x66, 0, 0, ...tiff];
	return Buffer.concat([jpg.subarray(0, 2), Buffer.from([0xff, 0xe1, (body.length + 2) >> 8, (body.length + 2) & 255, ...body]), jpg.subarray(2)]);
}

const tmp = fs.mkdtempSync(path.join(out, '.src-'));
function im(name, w, h, args) {
	const src = path.join(tmp, `${w}x${h}.png`);
	if (!fs.existsSync(src)) fs.writeFileSync(src, png(source(w, h), w, h));
	const file = path.join(out, name + '.jpg');
	execFileSync('convert', [src, '-strip', ...args, file]);
	return file;
}
const cases = [
	['q90-444', 37, 29, ['-quality', '90', '-sampling-factor', '1x1']],
	['q75-422', 37, 29, ['-quality', '75', '-sampling-factor', '2x1']],
	['q75-420', 37, 29, ['-quality', '75', '-sampling-factor', '2x2']],
	['q75-440', 37, 29, ['-quality', '75', '-sampling-factor', '1x2']],
	['q75-411', 37, 29, ['-quality', '75', '-sampling-factor', '4x1']],
	['q100-420', 40, 24, ['-quality', '100', '-sampling-factor', '2x2']],
	['grey', 37, 29, ['-quality', '80', '-colorspace', 'Gray']],
	['cmyk', 37, 29, ['-quality', '85', '-colorspace', 'CMYK']],
	['progressive-420', 37, 29, ['-quality', '75', '-sampling-factor', '2x2', '-interlace', 'JPEG']],
	['progressive-444', 50, 33, ['-quality', '92', '-sampling-factor', '1x1', '-interlace', 'JPEG']],
	['progressive-grey', 37, 29, ['-quality', '70', '-colorspace', 'Gray', '-interlace', 'JPEG']],
	['narrow-420', 3, 21, ['-quality', '75', '-sampling-factor', '2x2']],
	['large-420', 161, 97, ['-quality', '60', '-sampling-factor', '2x2', '-interlace', 'JPEG']],
];
const files = [];
for (const [name, w, h, args] of cases) files.push([name, im(name, w, h, args)]);
const px = source(37, 29);
fs.writeFileSync(path.join(out, 'restart.jpg'), encode(px, 37, 29, 2, false));
fs.writeFileSync(path.join(out, 'restart-grey.jpg'), encode(px, 37, 29, 3, true));
files.push(['restart', path.join(out, 'restart.jpg')], ['restart-grey', path.join(out, 'restart-grey.jpg')]);
for (const o of [3, 6, 8]) {
	fs.writeFileSync(path.join(out, `orient${o}.jpg`), oriented(fs.readFileSync(path.join(out, 'q75-420.jpg')), o));
	files.push([`orient${o}`, path.join(out, `orient${o}.jpg`)]);
}
fs.rmSync(tmp, { recursive: true });

// Chromium's pixels
const browser = await pw.chromium.launch();
const page = await browser.newPage();
const index = [];
for (const [name, file] of files) {
	const r = await page.evaluate(async (b64) => {
		const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
		const bmp = await createImageBitmap(new Blob([bytes], { type: 'image/jpeg' }), { colorSpaceConversion: 'none', premultiplyAlpha: 'none' });
		const c = new OffscreenCanvas(bmp.width, bmp.height), g = c.getContext('2d');
		g.drawImage(bmp, 0, 0);
		return { w: bmp.width, h: bmp.height, data: Array.from(g.getImageData(0, 0, bmp.width, bmp.height).data) };
	}, fs.readFileSync(file).toString('base64'));
	fs.writeFileSync(path.join(out, name + '.rgba'), Buffer.from(r.data));
	index.push({ name, width: r.w, height: r.h });
}
await browser.close();
fs.writeFileSync(path.join(out, 'cases.json'), JSON.stringify(index, null, '\t') + '\n');
console.log(`jpeg-cases: ${index.length} cases (chromium ${browser.version()})`);
