// The pdf lane's check: page 1 of each corpus PDF as helder drew it
// (bin/pdf/ours) against pdf.js's (tests/pdf/ref), both over white.
// A page passes when, of the 3x3 blocks either one inks (off white by
// more than 24, averaged), at most INK are off by more than 24 between the
// two (so a mostly white page cannot hide a wrong paragraph), and of all
// its pixels at most PAGE; and when its text (Pdf.text: ToUnicode or the glyph names)
// has the characters pdf.js's getTextContent has (whitespace aside, in
// any order: TEXT of them at least). Writes bin/pdf/report.md and
// bin/pdf/report-contact.png (helder's, pdf.js's, the difference times four).
//
// Pages listed in tests/pdf/known.txt are expected to fail (a decoder
// missing): reported, not failing the lane.
//
//   node tests/pdf/check.mjs [ours dir] [ref dir] [report: its path without .md]
import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { decode, diff, encode } from "../canvas/compare.mjs";

const ours = process.argv[2] ?? "bin/pdf/ours", ref = process.argv[3] ?? "tests/pdf/ref", report = process.argv[4] ?? "bin/pdf/report";
const OFF = 24, BLOCK = 3, INK = 0.1, PAGE = 0.06, TEXT = 0.97;
// (a page's own share of the inked: CJK's dense strokes, a quarter pixel from pdf.js's baseline, differ in more blocks)
const OWN_INK = { cjk: 0.2 };

function flatten(img) {
	for (let i = 0; i < img.w * img.h; i++) {
		const a = img.px[i * 4 + 3] / 255;
		for (let k = 0; k < 3; k++) img.px[i * 4 + k] = Math.round(img.px[i * 4 + k] * a + 255 * (1 - a));
		img.px[i * 4 + 3] = 255;
	}
	return img;
}

// (of the blocks either inks, the share off by more than OFF: each image averaged over BLOCK x BLOCK
// pixels first, so two rasterizers' antialiased edges agree while a glyph missing or wrong does not)
function ink(a, b) {
	const w = Math.floor(a.w / BLOCK), h = Math.floor(a.h / BLOCK);
	let inked = 0, off = 0;
	for (let by = 0; by < h; by++)
		for (let bx = 0; bx < w; bx++) {
			let ia = 0, ib = 0, d = 0;
			for (let k = 0; k < 3; k++) {
				let sa = 0, sb = 0;
				for (let y = by * BLOCK; y < (by + 1) * BLOCK; y++)
					for (let x = bx * BLOCK; x < (bx + 1) * BLOCK; x++) {
						sa += a.px[(y * a.w + x) * 4 + k];
						sb += b.px[(y * a.w + x) * 4 + k];
					}
				sa /= BLOCK * BLOCK;
				sb /= BLOCK * BLOCK;
				ia = Math.max(ia, 255 - sa);
				ib = Math.max(ib, 255 - sb);
				d = Math.max(d, Math.abs(sa - sb));
			}
			if (ia > OFF || ib > OFF) {
				inked++;
				if (d > OFF) off++;
			}
		}
	return inked === 0 ? 0 : off / inked;
}

// (the share of the reference's characters, whitespace aside, ours has: a multiset's overlap over the larger)
function textScore(a, b) {
	const count = s => { const m = new Map(); for (const c of s.replace(/\s+/g, "")) m.set(c, (m.get(c) ?? 0) + 1); return m; };
	const ca = count(a), cb = count(b);
	let na = 0, nb = 0, both = 0;
	for (const v of ca.values()) na += v;
	for (const [c, v] of cb) { nb += v; both += Math.min(v, ca.get(c) ?? 0); }
	return Math.max(na, nb) === 0 ? 1 : both / Math.max(na, nb);
}

// (tests/pdf/known.txt: "page: why" for each page expected to fail)
const knownFile = new URL("./known.txt", import.meta.url);
const known = new Map(existsSync(knownFile) ? readFileSync(knownFile, "utf8").split("\n").filter(l => l && !l.startsWith("#")).map(l => [l.slice(0, l.indexOf(":")).trim(), l.slice(l.indexOf(":") + 1).trim()]) : []);
const names = readdirSync(ref).filter(f => f.endsWith(".png")).map(f => f.slice(0, -4)).sort();
const rows = [], sheet = [];
let failed = 0, knownFailed = 0;
const fixed = [];
for (const name of names) {
	let a;
	try { a = flatten(decode(readFileSync(`${ours}/${name}.png`))); } catch { rows.push(`| ${name} | missing | | | | | FAIL |`); failed++; continue; }
	const b = flatten(decode(readFileSync(`${ref}/${name}.png`)));
	if (a.w !== b.w || a.h !== b.h) { rows.push(`| ${name} | ${a.w}x${a.h} vs ${b.w}x${b.h} | | | | | FAIL |`); failed++; continue; }
	const r = diff(a, b), inkOff = ink(a, b);
	const refText = existsSync(`${ref}/${name}.txt`) ? readFileSync(`${ref}/${name}.txt`, "utf8") : "";
	const ourText = existsSync(`${ours}/${name}.txt`) ? readFileSync(`${ours}/${name}.txt`, "utf8") : "";
	const t = textScore(ourText, refText);
	const ok = inkOff <= (OWN_INK[name] ?? INK) && r.off <= PAGE && t >= TEXT;
	let verdict = ok ? "ok" : "FAIL";
	if (known.has(name)) {
		if (ok) fixed.push(name); else knownFailed++;
		verdict = ok ? "ok (listed as known: take it off)" : "known: " + known.get(name);
	} else if (!ok) failed++;
	rows.push(`| ${name} | ${r.max} | ${r.mean.toFixed(2)} | ${(r.off * 100).toFixed(2)}% | ${(inkOff * 100).toFixed(2)}% | ${(t * 100).toFixed(1)}% | ${verdict} |`);
	sheet.push({ a, b, d: r.image });
}
const table = [`| page | max | mean | off by > ${OFF} | of the inked ${BLOCK}x${BLOCK} (≤ ${INK * 100}%) | text (≥ ${TEXT * 100}%) | |`, "| --- | ---: | ---: | ---: | ---: | ---: | --- |", ...rows].join("\n");
writeFileSync(report + ".md", table + "\n");
console.log(table);
const cw = Math.max(...sheet.map(s => s.a.w)), gap = 4, W = cw * 3 + gap * 4;
const H = sheet.reduce((h, s) => h + s.a.h + gap, gap);
const px = Buffer.alloc(W * H * 4, 0xd0);
let y = gap;
for (const s of sheet) {
	[s.a.px, s.b.px, s.d].forEach((img, k) => {
		const x0 = gap + k * (cw + gap);
		for (let j = 0; j < s.a.h; j++) img.copy(px, ((y + j) * W + x0) * 4, j * s.a.w * 4, (j + 1) * s.a.w * 4);
	});
	y += s.a.h + gap;
}
writeFileSync(report + "-contact.png", encode(W, H, px));
console.log(`check: ${names.length - failed - knownFailed} of ${names.length} pages within tolerance, ${knownFailed} known failures${fixed.length ? ", passing though listed as known: " + fixed.join(", ") : ""} (${report}.md, ${report}-contact.png: ${ours} | ${ref} | difference)`);
if (failed > 0) process.exit(1);
