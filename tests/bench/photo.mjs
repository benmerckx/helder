// A photo-like 4K PNG for tests/bench/Jobs.hx: 3840x2160 RGBA8, a sky's
// gradient and a sun's glow over hills, textured by value noise at four
// octaves, with a sensor's grain; each row filtered as libpng chooses (the
// least sum of absolute differences), zlib at level 6, IDAT in 64 KB chunks
// (11.6 MB). The same bytes on every run (a fixed seed).
//
//   node tests/bench/photo.mjs <out.png>
import fs from 'node:fs';
import zlib from 'node:zlib';

const W = 3840, H = 2160;
let seed = 0x2545F491;
const rand = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296);

// value noise on a lattice of `cell` pixels, smoothly interpolated
function noise(cell, gw = Math.ceil(W / cell) + 2, gh = Math.ceil(H / cell) + 2) {
	const g = new Float32Array(gw * gh).map(() => rand());
	return (x, y) => {
		const fx = x / cell, fy = y / cell, ix = fx | 0, iy = fy | 0;
		let tx = fx - ix, ty = fy - iy;
		tx = tx * tx * (3 - 2 * tx);
		ty = ty * ty * (3 - 2 * ty);
		const a = g[iy * gw + ix], b = g[iy * gw + ix + 1], c = g[(iy + 1) * gw + ix], d = g[(iy + 1) * gw + ix + 1];
		return a + (b - a) * tx + (c - a) * ty + (a - b - c + d) * tx * ty;
	};
}
const octaves = [noise(480), noise(120), noise(30), noise(8)];
const tex = (x, y) => octaves[0](x, y) * 0.5 + octaves[1](x, y) * 0.25 + octaves[2](x, y) * 0.15 + octaves[3](x, y) * 0.1;
const clamp = v => v < 0 ? 0 : v > 255 ? 255 : v | 0;

const stride = W * 4, rgba = Buffer.alloc(stride * H);
for (let y = 0; y < H; y++) {
	const horizon = H * 0.55;
	for (let x = 0; x < W; x++) {
		const t = tex(x, y), o = y * stride + x * 4;
		const hill = H * 0.55 + Math.sin(x / 610) * 140 + Math.sin(x / 173 + 1.3) * 45 + (t - 0.5) * 60;
		let r, g, b;
		if (y < hill) {
			// sky: blue at the top to a warm haze at the horizon, the sun's glow
			const k = y / horizon, dx = x - W * 0.7, dy = y - H * 0.3, sun = Math.exp(-(dx * dx + dy * dy) / (2 * 260 * 260));
			r = 70 + 150 * k + 120 * sun + (t - 0.5) * 18;
			g = 120 + 100 * k + 100 * sun + (t - 0.5) * 18;
			b = 210 - 30 * k + 40 * sun + (t - 0.5) * 12;
		} else {
			// hills: greens and browns, darker further down
			const k = (y - hill) / (H - hill + 1), m = octaves[2](x, y);
			r = (60 + 70 * m) * (1 - 0.5 * k) + (t - 0.5) * 90;
			g = (95 + 60 * t) * (1 - 0.45 * k) + (t - 0.5) * 70;
			b = (40 + 30 * m) * (1 - 0.5 * k) + (t - 0.5) * 40;
		}
		const grain = (rand() - 0.5) * 16;
		rgba[o] = clamp(r + grain);
		rgba[o + 1] = clamp(g + grain);
		rgba[o + 2] = clamp(b + grain);
		rgba[o + 3] = 255;
	}
}

// the filters, the one with the least sum of absolute differences per row
const raw = Buffer.alloc((stride + 1) * H), trial = Buffer.alloc(stride);
const zero = Buffer.alloc(stride);
for (let y = 0; y < H; y++) {
	const cur = rgba.subarray(y * stride, (y + 1) * stride), prev = y > 0 ? rgba.subarray((y - 1) * stride, y * stride) : zero;
	let bestSum = Infinity;
	for (let f = 0; f < 5; f++) {
		let sum = 0;
		for (let i = 0; i < stride; i++) {
			const a = i >= 4 ? cur[i - 4] : 0, b = prev[i], c = i >= 4 ? prev[i - 4] : 0;
			let p;
			switch (f) {
				case 0: p = 0; break;
				case 1: p = a; break;
				case 2: p = b; break;
				case 3: p = (a + b) >> 1; break;
				default: {
					const pa = Math.abs(b - c), pb = Math.abs(a - c), pc = Math.abs(a + b - 2 * c);
					p = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
				}
			}
			const v = (cur[i] - p) & 255;
			trial[i] = v;
			sum += v < 128 ? v : 256 - v;
		}
		if (sum < bestSum) {
			bestSum = sum;
			raw[y * (stride + 1)] = f;
			trial.copy(raw, y * (stride + 1) + 1);
		}
	}
}

const crcTable = new Int32Array(256).map((_, n) => {
	let c = n;
	for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
	return c;
});
function crc(buf) {
	let c = -1;
	for (const b of buf) c = crcTable[(c ^ b) & 255] ^ (c >>> 8);
	return (c ^ -1) >>> 0;
}
function chunk(type, data) {
	const out = Buffer.alloc(12 + data.length);
	out.writeUInt32BE(data.length, 0);
	out.write(type, 4, 'latin1');
	data.copy(out, 8);
	out.writeUInt32BE(crc(out.subarray(4, 8 + data.length)), 8 + data.length);
	return out;
}
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(W, 0);
ihdr.writeUInt32BE(H, 4);
ihdr[8] = 8;
ihdr[9] = 6;
const z = zlib.deflateSync(raw, { level: 6 }), parts = [];
for (let p = 0; p < z.length; p += 65536) parts.push(chunk('IDAT', z.subarray(p, Math.min(z.length, p + 65536))));
fs.writeFileSync(process.argv[2], Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), ...parts, chunk('IEND', Buffer.alloc(0))]));
