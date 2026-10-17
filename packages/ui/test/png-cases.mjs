// Writes packages/ui/test/png/: small PNG files of every colour type and bit
// depth, tRNS transparency, each scanline filter (row y uses filter y % 5)
// and Adam7 interlacing, each with the RGBA8 pixels PngDecoder must give
// (<case>.rgba: straight alpha; samples under 8 bits scaled exactly, 16-bit
// ones to their high byte). UiTest decodes them (make ui-check).
//   node packages/ui/test/png-cases.mjs
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(here, 'png');
const W = 13, H = 11;

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
function paeth(a, b, c) {
	const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
	return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}
// rows of raw bytes, filtered (row j: filter j % 5)
function filtered(rows, bpp) {
	const parts = [];
	let prev = Buffer.alloc(rows.length ? rows[0].length : 0);
	rows.forEach((row, j) => {
		const f = j % 5, o = Buffer.alloc(row.length + 1);
		o[0] = f;
		for (let x = 0; x < row.length; x++) {
			const a = x >= bpp ? row[x - bpp] : 0, b = prev[x], c = x >= bpp ? prev[x - bpp] : 0;
			const pred = [0, a, b, (a + b) >> 1, paeth(a, b, c)][f];
			o[x + 1] = (row[x] - pred) & 0xff;
		}
		parts.push(o);
		prev = row;
	});
	return Buffer.concat(parts);
}
// a row of samples (each pixel: channels values of depth bits) packed
function pack(samples, depth) {
	if (depth === 16) {
		const b = Buffer.alloc(samples.length * 2);
		samples.forEach((v, i) => b.writeUInt16BE(v, 2 * i));
		return b;
	}
	if (depth === 8) return Buffer.from(samples);
	const b = Buffer.alloc(Math.ceil(samples.length * depth / 8));
	samples.forEach((v, i) => {
		const bit = i * depth;
		b[bit >> 3] |= v << (8 - depth - (bit & 7));
	});
	return b;
}

const PASSES = [[0, 0, 8, 8], [4, 0, 8, 8], [0, 4, 4, 8], [2, 0, 4, 4], [0, 2, 2, 4], [1, 0, 2, 2], [0, 1, 1, 2]];

// a case: its colour type, depth, the samples of pixel (x, y), the RGBA8
// expected of them, tRNS and PLTE
function write(name, { type, depth, sample, expect, plte, trns, interlace = 0 }) {
	const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[type];
	const bpp = Math.max(1, (channels * depth) >> 3);
	const passes = interlace ? PASSES : [[0, 0, 1, 1]];
	const data = [];
	for (const [x0, y0, dx, dy] of passes) {
		const rows = [];
		for (let y = y0; y < H; y += dy) {
			const s = [];
			for (let x = x0; x < W; x += dx) s.push(...sample(x, y));
			if (s.length) rows.push(pack(s, depth));
		}
		if (rows.length) data.push(filtered(rows, bpp));
	}
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(W, 0);
	ihdr.writeUInt32BE(H, 4);
	ihdr[8] = depth;
	ihdr[9] = type;
	ihdr[12] = interlace;
	const z = zlib.deflateSync(Buffer.concat(data), { level: 9 });
	// (the image data split over two IDAT chunks)
	const half = z.length >> 1;
	const file = Buffer.concat([
		Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
		chunk('IHDR', ihdr),
		...(plte ? [chunk('PLTE', Buffer.from(plte))] : []),
		...(trns ? [chunk('tRNS', Buffer.from(trns))] : []),
		chunk('tEXt', Buffer.from('Comment\0an ancillary chunk, skipped', 'latin1')),
		chunk('IDAT', z.subarray(0, half)),
		chunk('IDAT', z.subarray(half)),
		chunk('IEND', Buffer.alloc(0)),
	]);
	const rgba = Buffer.alloc(W * H * 4);
	for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) Buffer.from(expect(x, y)).copy(rgba, 4 * (y * W + x));
	fs.writeFileSync(path.join(out, name + '.png'), file);
	fs.writeFileSync(path.join(out, name + '.rgba'), rgba);
}

fs.mkdirSync(out, { recursive: true });
const v8 = (x, y, k) => (x * 37 + y * 53 + k * 91 + x * y * 7) & 0xff;
const v16 = (x, y, k) => (v8(x, y, k) << 8) | ((x * 11 + y * 5 + k) & 0xff);
for (const depth of [1, 2, 4, 8, 16]) {
	const max = (1 << depth) - 1;
	const g = (x, y) => depth === 16 ? v16(x, y, 0) : v8(x, y, 0) % (max + 1);
	const s8 = (v) => depth === 16 ? v >> 8 : Math.floor(v * 255 / max);
	write('grey' + depth, { type: 0, depth, sample: (x, y) => [g(x, y)], expect: (x, y) => [s8(g(x, y)), s8(g(x, y)), s8(g(x, y)), 255] });
}
write('grey1-interlaced', { type: 0, depth: 1, interlace: 1, sample: (x, y) => [(x + y) & 1], expect: (x, y) => ((x + y) & 1 ? [255, 255, 255, 255] : [0, 0, 0, 255]) });
// a grey colour key: value 3 of 4 bits is transparent
write('grey4-key', { type: 0, depth: 4, trns: [0, 3], sample: (x, y) => [(x + y) % 16], expect: (x, y) => { const v = (x + y) % 16; return [v * 17, v * 17, v * 17, v === 3 ? 0 : 255]; } });
for (const depth of [8, 16]) {
	const c = (x, y, k) => depth === 16 ? v16(x, y, k) : v8(x, y, k);
	const s8 = (v) => depth === 16 ? v >> 8 : v;
	write('rgb' + depth, { type: 2, depth, sample: (x, y) => [c(x, y, 0), c(x, y, 1), c(x, y, 2)], expect: (x, y) => [s8(c(x, y, 0)), s8(c(x, y, 1)), s8(c(x, y, 2)), 255] });
	write('greya' + depth, { type: 4, depth, sample: (x, y) => [c(x, y, 0), c(x, y, 3)], expect: (x, y) => [s8(c(x, y, 0)), s8(c(x, y, 0)), s8(c(x, y, 0)), s8(c(x, y, 3))] });
	write('rgba' + depth, { type: 6, depth, sample: (x, y) => [0, 1, 2, 3].map((k) => c(x, y, k)), expect: (x, y) => [0, 1, 2, 3].map((k) => s8(c(x, y, k))) });
	write('rgba' + depth + '-interlaced', { type: 6, depth, interlace: 1, sample: (x, y) => [0, 1, 2, 3].map((k) => c(x, y, k)), expect: (x, y) => [0, 1, 2, 3].map((k) => s8(c(x, y, k))) });
}
// an RGB colour key: (x, y) = (2, 3) gets the key colour
write('rgb8-key', { type: 2, depth: 8, trns: [0, 10, 0, 20, 0, 30],
	sample: (x, y) => (x === 2 && y === 3 ? [10, 20, 30] : [v8(x, y, 0) | 1, 40, 50]),
	expect: (x, y) => (x === 2 && y === 3 ? [10, 20, 30, 0] : [v8(x, y, 0) | 1, 40, 50, 255]) });
for (const depth of [1, 2, 4, 8]) {
	const n = Math.min(1 << depth, 200);
	const plte = [], trns = [];
	for (let i = 0; i < n; i++) plte.push((i * 47) & 0xff, (i * 91 + 3) & 0xff, (i * 13 + 200) & 0xff);
	// (alphas for the first half of the entries only: the rest are opaque)
	for (let i = 0; i < Math.ceil(n / 2); i++) trns.push((i * 67 + 10) & 0xff);
	const k = (x, y) => (x * 3 + y * 5) % n;
	const rgba = (i) => [plte[3 * i], plte[3 * i + 1], plte[3 * i + 2], i < trns.length ? trns[i] : 255];
	write('palette' + depth, { type: 3, depth, plte, trns, sample: (x, y) => [k(x, y)], expect: (x, y) => rgba(k(x, y)) });
	if (depth === 4) write('palette4-interlaced', { type: 3, depth, plte, trns, interlace: 1, sample: (x, y) => [k(x, y)], expect: (x, y) => rgba(k(x, y)) });
}
console.log('png-cases.mjs: wrote', fs.readdirSync(out).filter((f) => f.endsWith('.png')).length, 'cases to', out);
