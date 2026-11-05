// A PNG larger than a texture's side (the viewer-window lane: its tiles):
// width x height of gradients and a line every 500 pixels, RGB, written by
// node's zlib.
//
//   node apps/viewer/tests/bigpng.mjs out.png 9000 2000
import { deflateSync, crc32 } from "node:zlib";
import { writeFileSync } from "node:fs";

const [out, w, h] = [process.argv[2], +process.argv[3], +process.argv[4]];
const raw = Buffer.alloc((w * 3 + 1) * h);
for (let y = 0; y < h; y++) {
	const row = y * (w * 3 + 1);
	for (let x = 0; x < w; x++) {
		const p = row + 1 + 3 * x, line = x % 500 < 3;
		raw[p] = line ? 255 : (x * 255 / w) | 0;
		raw[p + 1] = line ? 255 : (y * 255 / h) | 0;
		raw[p + 2] = line ? 0 : 128;
	}
}
const chunk = (name, data) => {
	const b = Buffer.alloc(12 + data.length);
	b.writeUInt32BE(data.length, 0);
	b.write(name, 4, "latin1");
	data.copy(b, 8);
	b.writeUInt32BE(crc32(b.subarray(4, 8 + data.length)), 8 + data.length);
	return b;
};
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(w, 0);
ihdr.writeUInt32BE(h, 4);
ihdr[8] = 8;
ihdr[9] = 2;
writeFileSync(out, Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
