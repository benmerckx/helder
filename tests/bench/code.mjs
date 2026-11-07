// The code editor's frames (helder.ui.code, examples/code-editor on a
// 10,000-line TSX file, `helder run --headless --stats`): the frames of a
// keystroke (the key to its frame drawn), of the wheel's first pass down
// (lines laid out the first time) and of its pass back up (lines laid out
// already: the steady state), and the idle ones; each phase's median, p95
// and longest ms against the 8 ms budget, and its GC bytes a frame.
//   node tests/bench/code.mjs <stats.json> <phases.json> [--markdown]
import { readFileSync } from 'node:fs';

const [statsPath, phasesPath, flag] = process.argv.slice(2);
const stats = JSON.parse(readFileSync(statsPath, 'utf8'));
const phases = JSON.parse(readFileSync(phasesPath, 'utf8'));
const BUDGET = 8;

function pct(a, p) {
	if (a.length === 0) return NaN;
	const s = [...a].sort((x, y) => x - y);
	return s[Math.min(s.length - 1, Math.floor(p * (s.length - 1) + 0.5))];
}

const rows = [];
for (const ph of phases) {
	const fs = stats.frames.filter((f) => f.t >= ph.from && f.t < ph.to && (ph.kind === 'idle' ? f.keys + f.wheels + f.pointers === 0 : f[ph.kind] > 0));
	const ms = fs.map((f) => f.ms), bytes = fs.map((f) => f.gcBytes);
	const over = ms.filter((m) => m > BUDGET).length;
	rows.push({ name: ph.name, frames: fs.length, median: pct(ms, 0.5), p95: pct(ms, 0.95), max: Math.max(...ms), over, bytes: pct(bytes, 0.5), bytesMax: Math.max(...bytes), gcs: fs.reduce((s, f) => s + f.gcs, 0) });
}
const r = (x) => (Number.isFinite(x) ? Math.round(x * 100) / 100 : '-');
if (flag === '--markdown') {
	console.log('| phase | frames | median ms | p95 ms | max ms | over 8 ms | GC bytes/frame (median) | max | GCs |');
	console.log('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
	for (const x of rows) console.log(`| ${x.name} | ${x.frames} | ${r(x.median)} | ${r(x.p95)} | ${r(x.max)} | ${x.over} | ${x.bytes} | ${x.bytesMax} | ${x.gcs} |`);
} else {
	for (const x of rows)
		console.log(`code-bench: ${x.name.padEnd(34)} ${String(x.frames).padStart(4)} frames, median ${r(x.median)} ms, p95 ${r(x.p95)} ms, max ${r(x.max)} ms (${x.over} over ${BUDGET} ms), ${x.bytes} GC bytes a frame (max ${x.bytesMax}), ${x.gcs} GCs`);
}
