// The screen fixture's lines (tests/pack/Screen.hx: logcat's on CI's
// emulator, simctl's on its simulator; tests/pack/android.sh and ios.sh)
// checked: the window's size and scale; the safe area before the bars were
// hidden (Android: the navigation bar's bottom inset; iOS: the notch's or
// the island's top and the home indicator's bottom); the display's frames
// (vsyncs, their mean delta and period a display's: 5 to 50 ms) and nothing
// allocated over 120; Android: the bars hidden (no bottom inset) and the
// window into the cutout (a top inset), then a rotation (a Resize wider
// than high, the cutout at a side);
// the background (Suspend) and back (Resume, the first frame's delta a
// period, not the time away). Exits non-zero on a failure.
//   node tests/pack/screen.mjs <lines> android|ios
import fs from 'node:fs';

const [file, platform] = process.argv.slice(2);
const lines = fs.readFileSync(file, 'utf8').split('\n').map((l) => l.replace(/^.*?(screen: )/, '$1').trim()).filter((l) => l.startsWith('screen: '));
let failed = 0;
const check = (what, ok, detail = '') => {
	console.log(`screen.mjs: ${what}: ${ok ? 'ok' : 'FAIL'}${detail ? '  ' + detail : ''}`);
	if (!ok) failed++;
};
for (const l of lines) console.log('  ' + l);
const find = (re, from = 0) => {
	for (let i = from; i < lines.length; i++) {
		const m = re.exec(lines[i]);
		if (m) return { m, i };
	}
	return null;
};
const safe = (s) => s.split(',').map(Number); // top,left,bottom,right

const win = find(/^screen: window (\d+)x(\d+) scale ([\d.]+) safe ([\d,]+)/);
check('the window: a size and a scale', win && +win.m[1] > 0 && +win.m[2] > 0 && +win.m[3] >= (platform === 'ios' ? 2 : 1), win?.m[0]);
const immersive = find(/^screen: immersive/)?.i ?? lines.length;
// (the safe area before the bars were hidden: the window's line, its Resizes)
const before = lines.slice(0, immersive).map((l) => /safe ([\d,]+)/.exec(l)).filter(Boolean).map((m) => safe(m[1]));
const most = (k) => Math.max(0, ...before.map((s) => s[k]));
if (platform === 'ios') {
	check('the safe area: the top (the notch, the island)', most(0) > 0, `top ${most(0)}`);
	check("the safe area: the bottom (the home indicator)", most(2) > 0, `bottom ${most(2)}`);
} else check('the safe area: the bottom (the navigation bar)', most(2) > 0, `bottom ${most(2)}`);
const first = lines.filter((l) => /^screen: frame \d+ /.test(l));
check("the first frames: the display's vsyncs", first.length === 5 && first.every((l) => l.endsWith('vsync true')), first.length + ' lines');
const frames = find(/^screen: frames 120 mean ([\d.]+) min ([\d.]+) max ([\d.]+) period ([\d.]+) vsync (\w+)/);
check("120 frames: a display's pace (5 to 50 ms)", frames && +frames.m[1] >= 5 && +frames.m[1] <= 50 && +frames.m[4] >= 5 && +frames.m[4] <= 50 && frames.m[5] === 'true', frames?.m[0]);
const alloc = find(/^screen: allocated (-?\d+) bytes/);
check('120 frames: nothing allocated', alloc && +alloc.m[1] === 0, alloc?.m[0]);
if (platform === 'android') {
	// (the window's Resizes once immersive: into the cutout's edge (the
	// Pixel 6's camera: a top inset upright, a side's turned), the bars
	// hidden (no bottom inset); the first may come before its insets were
	// measured again, the next with them)
	const resizes = lines.slice(immersive).map((l) => /^screen: resize (\d+)x(\d+) .* safe ([\d,]+)/.exec(l)).filter(Boolean);
	const upright = resizes.find((m) => +m[1] < +m[2] && safe(m[3])[2] === 0 && safe(m[3])[0] > 0);
	check('immersive: the bars hidden (no bottom inset), the window into the cutout (a top inset)', !!upright, upright?.[0]);
	const turned = resizes.find((m) => +m[1] > +m[2]);
	check('a rotation: a Resize wider than high', !!turned, turned?.[0]);
	check('turned: the cutout at a side', turned && (safe(turned[3])[1] > 0 || safe(turned[3])[3] > 0), turned?.[0]);
}
const suspend = find(/^screen: suspend/);
check('the background: Suspend', !!suspend);
const resume = find(/^screen: resume/, suspend ? suspend.i : 0);
check('back: Resume', !!resume, resume?.m[0]);
const again = find(/^screen: first frame after resume: delta ([\d.]+) ms, period ([\d.]+) ms/, resume ? resume.i : 0);
check("the first frame after it: a period's delta, not the time away", again && +again.m[1] <= 50, again?.m[0]);
process.exit(failed ? 1 : 0);
