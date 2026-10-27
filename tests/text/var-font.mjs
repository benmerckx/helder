// The variable font of TextTest's variation checks, and Chromium's
// measures of it: writes var.ttf (VarTest, one axis, wght 100 to 900, 400
// by default; avar maps 0.5 to 0.25) whose glyphs each exercise a part of
// gvar: A, every point moved (a tuple at each end of the axis); B, two
// points named, the others inferred (IUP); C, a composite of two A's, the
// second moved; D, an intermediate region (peaking at 0.5); then, unless
// --font-only, Chromium's advance and ink bounds of each at several
// weights (canvas measureText at 1000px: font units; the FontFace's weight
// range maps font-weight to wght) into var-expected.json. Run it after
// changing the font (Playwright from npm, with Chromium):
//   node tests/text/var-font.mjs [--font-only]
import { writeFileSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const u16 = (v) => [(v >> 8) & 255, v & 255];
const s16 = (v) => u16(v < 0 ? v + 65536 : v);
const u32 = (v) => [(v >>> 24) & 255, (v >>> 16) & 255, (v >>> 8) & 255, v & 255];
const f2 = (v) => s16(Math.round(v * 16384));
const fixed = (v) => u32(Math.round(v * 65536) >>> 0);
const pad4 = (a) => { while (a.length % 4) a.push(0); return a; };

// glyphs: simple (one contour of on-curve points) or composite
const rect = (x0, y0, x1, y1) => [[x0, y0], [x1, y0], [x1, y1], [x0, y1]];
const glyphs = [
	{ name: '.notdef', adv: 500, points: [] },
	{ name: 'A', cp: 0x41, adv: 500, points: rect(50, 0, 450, 700) },
	{ name: 'B', cp: 0x42, adv: 500, points: [[50, 0], [250, 0], [450, 0], [450, 350], [450, 700], [250, 700], [50, 700], [50, 350]] },
	{ name: 'C', cp: 0x43, adv: 1000, components: [[1, 0, 0], [1, 500, 0]] },
	{ name: 'D', cp: 0x44, adv: 500, points: rect(50, 0, 450, 600) },
];
// tuples per glyph: peak (normalized), [start, end] for an intermediate region, points (null: all, phantom points last), x and y deltas
const tuples = [
	[],
	[{ peak: 1, points: null, x: [0, 300, 300, 0, 0, 300, 0, 0], y: [0, 0, 0, 0, 0, 0, 0, 0] },
		{ peak: -1, points: null, x: [0, -100, -100, 0, 0, -100, 0, 0], y: [0, 0, 0, 0, 0, 0, 0, 0] }],
	[{ peak: 1, points: [0, 4, 9], x: [0, 200, 200], y: [0, 100, 0] }],
	[{ peak: 1, points: null, x: [0, 300, 0, 600, 0, 0], y: [0, 50, 0, 0, 0, 0] }],
	[{ peak: 0.5, region: [0, 1], points: null, x: [0, 100, 100, 0, 0, 100, 0, 0], y: [0, 0, 50, 50, 0, 0, 0, 0] }],
];

function bbox(g) {
	if (g.components) {
		const pts = g.components.flatMap(([i, dx, dy]) => glyphs[i].points.map(([x, y]) => [x + dx, y + dy]));
		return [Math.min(...pts.map((p) => p[0])), Math.min(...pts.map((p) => p[1])), Math.max(...pts.map((p) => p[0])), Math.max(...pts.map((p) => p[1]))];
	}
	if (g.points.length == 0) return [0, 0, 0, 0];
	return [Math.min(...g.points.map((p) => p[0])), Math.min(...g.points.map((p) => p[1])), Math.max(...g.points.map((p) => p[0])), Math.max(...g.points.map((p) => p[1]))];
}

function glyf(g) {
	if (!g.components && g.points.length == 0) return [];
	const b = bbox(g);
	if (g.components) {
		const out = [...s16(-1), ...s16(b[0]), ...s16(b[1]), ...s16(b[2]), ...s16(b[3])];
		g.components.forEach(([i, dx, dy], k) => {
			const more = k < g.components.length - 1 ? 0x20 : 0;
			out.push(...u16(0x1 | 0x2 | more), ...u16(i), ...s16(dx), ...s16(dy));
		});
		return out;
	}
	const n = g.points.length;
	const out = [...s16(1), ...s16(b[0]), ...s16(b[1]), ...s16(b[2]), ...s16(b[3]), ...u16(n - 1), ...u16(0)];
	for (let i = 0; i < n; i++) out.push(1);
	let last = 0;
	for (const [x] of g.points) { out.push(...s16(x - last)); last = x; }
	last = 0;
	for (const [, y] of g.points) { out.push(...s16(y - last)); last = y; }
	return out;
}

function packPoints(points) {
	if (points == null) return [0];
	const out = [points.length, points.length - 1];
	let last = 0;
	for (const p of points) { out.push(p - last); last = p; }
	return out;
}
const packDeltas = (ds) => [0x40 | (ds.length - 1), ...ds.flatMap(s16)];

function gvarData(ts) {
	if (ts.length == 0) return [];
	const headers = [], data = [];
	for (const t of ts) {
		const body = [...packPoints(t.points), ...packDeltas(t.x), ...packDeltas(t.y)];
		headers.push(...u16(body.length), ...u16(0x8000 | 0x2000 | (t.region ? 0x4000 : 0)), ...f2(t.peak));
		if (t.region) headers.push(...f2(t.region[0]), ...f2(t.region[1]));
		data.push(...body);
	}
	return pad4([...u16(ts.length), ...u16(4 + headers.length), ...headers, ...data]);
}

function nameTable() {
	const names = [[1, 'VarTest'], [2, 'Regular'], [3, 'VarTest-Regular'], [4, 'VarTest Regular'], [6, 'VarTest-Regular'], [256, 'Weight']];
	const strings = names.map(([, s]) => [...s].flatMap((c) => u16(c.charCodeAt(0))));
	const out = [...u16(0), ...u16(names.length), ...u16(6 + 12 * names.length)];
	let off = 0;
	names.forEach(([id], i) => { out.push(...u16(3), ...u16(1), ...u16(0x409), ...u16(id), ...u16(strings[i].length), ...u16(off)); off += strings[i].length; });
	for (const s of strings) out.push(...s);
	return out;
}

function font() {
	const glyphData = glyphs.map((g) => pad4(glyf(g)));
	const loca = [];
	let off = 0;
	for (const d of glyphData) { loca.push(...u32(off)); off += d.length; }
	loca.push(...u32(off));
	const all = glyphs.map(bbox).filter((b) => b[2] > b[0]);
	const fb = [Math.min(...all.map((b) => b[0])), Math.min(...all.map((b) => b[1])), Math.max(...all.map((b) => b[2])), Math.max(...all.map((b) => b[3]))];
	const head = [...u32(0x10000), ...u32(0x10000), ...u32(0), ...u32(0x5F0F3CF5), ...u16(0x000B), ...u16(1000), ...u32(0), ...u32(0), ...u32(0), ...u32(0),
		...s16(fb[0]), ...s16(fb[1]), ...s16(fb[2]), ...s16(fb[3]), ...u16(0), ...u16(8), ...s16(2), ...s16(1), ...s16(0)];
	const hhea = [...u32(0x10000), ...s16(800), ...s16(-200), ...s16(0), ...u16(1000), ...s16(50), ...s16(50), ...s16(fb[2]), ...s16(1), ...s16(0), ...s16(0),
		...s16(0), ...s16(0), ...s16(0), ...s16(0), ...s16(0), ...u16(glyphs.length)];
	const maxp = [...u32(0x10000), ...u16(glyphs.length), ...u16(8), ...u16(1), ...u16(8), ...u16(1), ...u16(2), ...u16(0), ...u16(0), ...u16(0), ...u16(0),
		...u16(0), ...u16(0), ...u16(2), ...u16(1)];
	const hmtx = glyphs.flatMap((g) => [...u16(g.adv), ...s16(bbox(g)[0])]);
	const cps = glyphs.filter((g) => g.cp);
	const first = cps[0].cp, last = cps[cps.length - 1].cp;
	const sub = [...u16(4), ...u16(32), ...u16(0), ...u16(4), ...u16(4), ...u16(1), ...u16(0),
		...u16(last), ...u16(0xFFFF), ...u16(0), ...u16(first), ...u16(0xFFFF), ...s16(1 - first), ...s16(1), ...u16(0), ...u16(0)];
	const cmap = [...u16(0), ...u16(1), ...u16(3), ...u16(1), ...u32(12), ...sub];
	const os2 = [...u16(4), ...s16(500), ...u16(400), ...u16(5), ...u16(0), ...s16(650), ...s16(700), ...s16(0), ...s16(140), ...s16(650), ...s16(700), ...s16(0), ...s16(480),
		...s16(50), ...s16(250), ...s16(0), ...new Array(10).fill(0), ...u32(1), ...u32(0), ...u32(0), ...u32(0), ...[...'NONE'].map((c) => c.charCodeAt(0)),
		...u16(0x40), ...u16(first), ...u16(last), ...s16(800), ...s16(-200), ...s16(0), ...u16(800), ...u16(200), ...u32(1), ...u32(0), ...s16(500), ...s16(700),
		...u16(0), ...u16(0x20), ...u16(0)];
	const post = [...u32(0x30000), ...u32(0), ...s16(-100), ...s16(50), ...u32(0), ...u32(0), ...u32(0), ...u32(0), ...u32(0)];
	const fvar = [...u16(1), ...u16(0), ...u16(16), ...u16(2), ...u16(1), ...u16(20), ...u16(0), ...u16(8),
		...[...'wght'].map((c) => c.charCodeAt(0)), ...fixed(100), ...fixed(400), ...fixed(900), ...u16(0), ...u16(256)];
	const avar = [...u16(1), ...u16(0), ...u16(0), ...u16(1), ...u16(4), ...f2(-1), ...f2(-1), ...f2(0), ...f2(0), ...f2(0.5), ...f2(0.25), ...f2(1), ...f2(1)];
	const varData = tuples.map(gvarData);
	const gvarHead = 20 + 4 * (glyphs.length + 1);
	const gvar = [...u16(1), ...u16(0), ...u16(1), ...u16(0), ...u32(gvarHead), ...u16(glyphs.length), ...u16(1), ...u32(gvarHead)];
	off = 0;
	for (const d of varData) { gvar.push(...u32(off)); off += d.length; }
	gvar.push(...u32(off));
	for (const d of varData) gvar.push(...d);
	const tables = { 'OS/2': os2, avar, cmap, fvar, glyf: glyphData.flat(), gvar, head, hhea, hmtx, loca, maxp, name: nameTable(), post };
	const tags = Object.keys(tables).sort();
	const n = tags.length;
	let sr = 1, es = 0;
	while (sr * 2 <= n) { sr *= 2; es++; }
	const out = [...u32(0x10000), ...u16(n), ...u16(sr * 16), ...u16(es), ...u16(n * 16 - sr * 16)];
	let at = 12 + 16 * n;
	const body = [];
	for (const t of tags) {
		const d = tables[t];
		let sum = 0;
		const p = pad4([...d]);
		for (let i = 0; i < p.length; i += 4) sum = (sum + ((p[i] << 24) | (p[i + 1] << 16) | (p[i + 2] << 8) | p[i + 3])) >>> 0;
		out.push(...[...t].map((c) => c.charCodeAt(0)), ...u32(sum), ...u32(at), ...u32(d.length));
		body.push(...p);
		at += p.length;
	}
	return Buffer.from([...out, ...body]);
}

const file = path.join(here, 'var.ttf');
writeFileSync(file, font());
console.log('var-font.mjs: wrote', file);
if (process.argv.includes('--font-only')) process.exit(0);

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const browser = await pw.chromium.launch();
const page = await browser.newPage();
const weights = [100, 250, 400, 500, 600, 650, 700, 900];
const b64 = readFileSync(file).toString('base64');
const measured = await page.evaluate(async ({ b64, weights }) => {
	const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
	const face = new FontFace('VarTest', bytes.buffer, { weight: '100 900' });
	await face.load();
	document.fonts.add(face);
	const ctx = document.createElement('canvas').getContext('2d');
	const out = [];
	for (const ch of ['A', 'B', 'C', 'D'])
		for (const w of weights) {
			ctx.font = `${w} 1000px VarTest`;
			const m = ctx.measureText(ch);
			out.push({ ch, weight: w, advance: m.width, left: -m.actualBoundingBoxLeft, right: m.actualBoundingBoxRight, top: m.actualBoundingBoxAscent });
		}
	return out;
}, { b64, weights });
await browser.close();
writeFileSync(path.join(here, 'var-expected.json'), JSON.stringify(measured, null, '\t') + '\n');
console.log(`var-font.mjs: ${measured.length} measures (chromium ${browser.version()})`);
