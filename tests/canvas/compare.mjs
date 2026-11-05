// The canvas lane's check: each scene helder drew (bin/canvas/ours)
// against Chromium's (tests/canvas/ref), pixel by pixel on premultiplied
// values: the largest difference, the mean, the share of pixels off by
// more than 24 (of 255). A scene passes when that share is within its
// tolerance (TOLERANCE below: text is rasterised by two engines, so its
// edges differ more). Writes bin/canvas/report.md and a contact sheet,
// bin/canvas/contact.png (each scene: helder's, Chromium's, the
// difference times four).
//
//   node tests/canvas/compare.mjs [ours dir] [ref dir]
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import zlib from "node:zlib";

const ours = process.argv[2] ?? "bin/canvas/ours", ref = process.argv[3] ?? "tests/canvas/ref";
const OFF = 24;
// (the share of pixels off by more than OFF a scene may have)
const TOLERANCE = { default: 0.01, "text-": 0.06 };

export function decode(buf) {
	if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error("not a PNG");
	let p = 8, w = 0, h = 0, type = 0, depth = 0;
	const idat = [];
	while (p < buf.length) {
		const len = buf.readUInt32BE(p), kind = buf.toString("latin1", p + 4, p + 8), data = buf.subarray(p + 8, p + 8 + len);
		if (kind === "IHDR") {
			w = data.readUInt32BE(0);
			h = data.readUInt32BE(4);
			depth = data[8];
			type = data[9];
			if (depth !== 8 || data[12] !== 0 || (type !== 6 && type !== 2)) throw new Error(`unsupported PNG: depth ${depth}, type ${type}`);
		} else if (kind === "IDAT") idat.push(data);
		p += 12 + len;
	}
	const raw = zlib.inflateSync(Buffer.concat(idat)), bpp = type === 6 ? 4 : 3, stride = w * bpp;
	const px = Buffer.alloc(w * h * 4), prev = Buffer.alloc(stride), cur = Buffer.alloc(stride);
	for (let y = 0; y < h; y++) {
		const f = raw[y * (stride + 1)];
		for (let i = 0; i < stride; i++) {
			const x = raw[y * (stride + 1) + 1 + i], a = i >= bpp ? cur[i - bpp] : 0, b = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
			let v;
			if (f === 0) v = x;
			else if (f === 1) v = x + a;
			else if (f === 2) v = x + b;
			else if (f === 3) v = x + ((a + b) >> 1);
			else {
				const pp = a + b - c, pa = Math.abs(pp - a), pb = Math.abs(pp - b), pc = Math.abs(pp - c);
				v = x + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c);
			}
			cur[i] = v & 255;
		}
		for (let xx = 0; xx < w; xx++) {
			const o = (y * w + xx) * 4;
			px[o] = cur[xx * bpp];
			px[o + 1] = cur[xx * bpp + 1];
			px[o + 2] = cur[xx * bpp + 2];
			px[o + 3] = bpp === 4 ? cur[xx * bpp + 3] : 255;
		}
		cur.copy(prev);
	}
	return { w, h, px };
}

export function encode(w, h, px) {
	const raw = Buffer.alloc((w * 4 + 1) * h);
	for (let y = 0; y < h; y++) px.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
	const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
	const crc = b => { let c = 0xffffffff; for (const x of b) c = crcTable[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
	const chunk = (kind, data) => {
		const b = Buffer.alloc(12 + data.length);
		b.writeUInt32BE(data.length, 0);
		b.write(kind, 4, "latin1");
		data.copy(b, 8);
		b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length);
		return b;
	};
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(w, 0);
	ihdr.writeUInt32BE(h, 4);
	ihdr[8] = 8;
	ihdr[9] = 6;
	return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

// two images' differences on premultiplied values, and the difference image (times four, on white)
export function diff(a, b) {
	let max = 0, sum = 0, off = 0;
	const n = a.w * a.h, d = Buffer.alloc(n * 4);
	for (let i = 0; i < n; i++) {
		let m = 0;
		for (let k = 0; k < 4; k++) {
			const va = k === 3 ? a.px[i * 4 + 3] : a.px[i * 4 + k] * a.px[i * 4 + 3] / 255;
			const vb = k === 3 ? b.px[i * 4 + 3] : b.px[i * 4 + k] * b.px[i * 4 + 3] / 255;
			m = Math.max(m, Math.abs(va - vb));
		}
		m = Math.round(m);
		if (m > max) max = m;
		sum += m;
		if (m > OFF) off++;
		const v = Math.max(0, 255 - m * 4);
		d[i * 4] = 255;
		d[i * 4 + 1] = v;
		d[i * 4 + 2] = v;
		d[i * 4 + 3] = 255;
	}
	return { max, mean: sum / n, off: off / n, image: d };
}

function tolerance(name) {
	for (const [k, v] of Object.entries(TOLERANCE)) if (k !== "default" && name.startsWith(k)) return v;
	return TOLERANCE.default;
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith("compare.mjs")) {
	const names = readdirSync(ref).filter(f => f.endsWith(".png")).map(f => f.slice(0, -4)).sort();
	const rows = [], sheet = [];
	let failed = 0;
	for (const name of names) {
		let a;
		try { a = decode(readFileSync(`${ours}/${name}.png`)); } catch (e) { rows.push(`| ${name} | missing | | | FAIL |`); failed++; continue; }
		const b = decode(readFileSync(`${ref}/${name}.png`));
		if (a.w !== b.w || a.h !== b.h) { rows.push(`| ${name} | ${a.w}x${a.h} vs ${b.w}x${b.h} | | | FAIL |`); failed++; continue; }
		const r = diff(a, b), ok = r.off <= tolerance(name);
		if (!ok) failed++;
		rows.push(`| ${name} | ${r.max} | ${r.mean.toFixed(2)} | ${(r.off * 100).toFixed(2)}% | ${ok ? "ok" : "FAIL"} |`);
		sheet.push({ name, a, b, d: r.image });
	}
	const report = [`| scene | max | mean | off by > ${OFF} | |`, "| --- | ---: | ---: | ---: | --- |", ...rows].join("\n");
	writeFileSync("bin/canvas/report.md", report + "\n");
	console.log(report);
	// (the contact sheet: a row per scene, 4 px apart)
	const cw = Math.max(...sheet.map(s => s.a.w)), gap = 4, W = cw * 3 + gap * 4;
	const H = sheet.reduce((h, s) => h + s.a.h + gap, gap);
	const px = Buffer.alloc(W * H * 4, 0xd0);
	let y = gap;
	for (const s of sheet) {
		[s.a.px, s.b.px, s.d].forEach((img, k) => {
			const x0 = gap + k * (cw + gap);
			for (let j = 0; j < s.a.h; j++)
				for (let i = 0; i < s.a.w; i++) {
					const o = (j * s.a.w + i) * 4, t = ((y + j) * W + x0 + i) * 4, al = img[o + 3] / 255;
					// (over a checkerboard: transparency shown)
					const bg = ((i >> 3) + (j >> 3)) % 2 ? 0xcc : 0xff;
					for (let c = 0; c < 3; c++) px[t + c] = Math.round(img[o + c] * al + bg * (1 - al));
					px[t + 3] = 255;
				}
		});
		y += s.a.h + gap;
	}
	writeFileSync("bin/canvas/contact.png", encode(W, H, px));
	console.log(`compare: ${names.length - failed} of ${names.length} scenes within tolerance (bin/canvas/report.md, bin/canvas/contact.png: helder | Chromium | difference)`);
	if (failed > 0) process.exit(1);
}
