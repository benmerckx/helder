// Compresses PNG files in place, their pixels the same: the IDAT data inflated
// and deflated again (level 9). The tests write PNGs in stored blocks
// (Png.encode); run this on goldens written by --bless before committing them.
//   node packages/gfx/test/png-deflate.mjs <file.png>...
import fs from 'node:fs';
import zlib from 'node:zlib';
function crc32(b) { let r = 0xffffffff; for (const x of b) { r ^= x; for (let k = 0; k < 8; k++) r = r & 1 ? 0xedb88320 ^ (r >>> 1) : r >>> 1; } return (r ^ 0xffffffff) >>> 0; }
for (const f of process.argv.slice(2)) {
	const b = fs.readFileSync(f); let o = 8; const chunks = []; const idat = [];
	while (o < b.length) { const n = b.readUInt32BE(o), t = b.toString('latin1', o + 4, o + 8), d = b.subarray(o + 8, o + 8 + n); if (t === 'IDAT') idat.push(d); else chunks.push([t, d]); o += 12 + n; }
	const raw = zlib.inflateSync(Buffer.concat(idat)), z = zlib.deflateSync(raw, { level: 9 });
	const out = [b.subarray(0, 8)];
	const chunk = (t, d) => { const h = Buffer.alloc(8), c = Buffer.alloc(4); h.writeUInt32BE(d.length, 0); h.write(t, 4, 'latin1'); c.writeUInt32BE(crc32(Buffer.concat([Buffer.from(t, 'latin1'), d])), 0); return Buffer.concat([h, d, c]); };
	for (const [t, d] of chunks) { if (t === 'IEND') out.push(chunk('IDAT', z)); out.push(chunk(t, d)); }
	fs.writeFileSync(f, Buffer.concat(out)); console.log(f, b.length, '->', fs.statSync(f).size);
}
