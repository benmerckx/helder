// examples/million's frames (a VirtualList of a million rows, `helder run
// --headless --stats` on the million-bench lane's script): its first frame,
// the wheel over rows made the first time and over rows made before, the
// jumps (End, Top), the rows put in above the view, the keyboard's Down and
// idle; each phase's median, p95 and longest ms against the 8 ms budget and
// its GC bytes a frame (the frames of the phase's input: a tap's its release's).
//   node tests/bench/million.mjs <stats.json> <script.json> [--markdown]
import { readFileSync } from 'node:fs';

const [statsPath, scriptPath, flag] = process.argv.slice(2);
const stats = JSON.parse(readFileSync(statsPath, 'utf8'));
const marks = Object.fromEntries(JSON.parse(readFileSync(scriptPath, 'utf8')).events.filter((e) => e.type === 'mark').map((e) => [e.name, e.t]));
const BUDGET = 8;
const phases = [
	{ name: 'first frame (a million rows, the view made)', frames: stats.frames.slice(0, 1) },
	{ name: 'wheel, rows made the first time', from: marks.down, to: marks.again, kind: 'wheels' },
	{ name: 'wheel over rows made before', from: marks.again, to: marks.jumps, kind: 'wheels' },
	{ name: 'End and Top (a jump, the rows there made)', from: marks.jumps, to: marks.inserts, kind: 'pointers' },
	{ name: 'three rows put in above the view', from: marks.inserts, to: marks.keys - 0.2, kind: 'pointers' },
	{ name: 'the keyboard\'s Down', from: marks.keys, to: marks.idle, kind: 'keys' },
	{ name: 'idle', from: marks.idle + 0.1, to: marks.end, kind: 'idle' }
];

function pct(a, p) {
	if (a.length === 0) return NaN;
	const s = [...a].sort((x, y) => x - y);
	return s[Math.min(s.length - 1, Math.floor(p * (s.length - 1) + 0.5))];
}

const rows = [];
for (const ph of phases) {
	const fs = ph.frames ?? stats.frames.filter((f) => f.t >= ph.from && f.t < ph.to && (ph.kind === 'idle' ? f.keys + f.wheels + f.pointers === 0 : f[ph.kind] > 0));
	const ms = fs.map((f) => f.ms), bytes = fs.map((f) => f.gcBytes);
	rows.push({ name: ph.name, frames: fs.length, median: pct(ms, 0.5), p95: pct(ms, 0.95), max: Math.max(...ms), over: ms.filter((m) => m > BUDGET).length, bytes: pct(bytes, 0.5), bytesMax: Math.max(...bytes), gcs: fs.reduce((s, f) => s + f.gcs, 0) });
}
const r = (x) => (Number.isFinite(x) ? Math.round(x * 100) / 100 : '-');
if (flag === '--markdown') {
	console.log('| phase | frames | median ms | p95 ms | max ms | over 8 ms | GC bytes a frame (median) | max | GCs |');
	console.log('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
	for (const x of rows) console.log(`| ${x.name} | ${x.frames} | ${r(x.median)} | ${r(x.p95)} | ${r(x.max)} | ${x.over} | ${x.bytes} | ${x.bytesMax} | ${x.gcs} |`);
} else {
	for (const x of rows)
		console.log(`million-bench: ${x.name.padEnd(44)} ${String(x.frames).padStart(4)} frames, median ${r(x.median)} ms, p95 ${r(x.p95)} ms, max ${r(x.max)} ms (${x.over} over ${BUDGET} ms), ${x.bytes} GC bytes a frame (max ${x.bytesMax}), ${x.gcs} GCs`);
}
