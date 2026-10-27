// Random flex trees against Chromium: COUNT trees from SEED (directions,
// wrapping, alignment, grow, shrink, basis, sizes, min and max in pixels
// or percentages, padding, margins, borders, gaps), their boxes read back
// as layout-ref.mjs reads them, into OUT's layout-cases.json and
// layout-expected.json, which LayoutFuzz lays out and compares (make
// ui-layout-fuzz SEED=1 COUNT=200). A difference found: reduce it
// (layout-reduce.mjs) to a case in layout-cases.mjs. With 'more' (FEATURES=more):
// grids and their placement, absolute positions, auto margins, order,
// aspect ratios, hidden overflow and display none too (the plain trees of a
// seed the same without it).
//   node tests/ui/layout-fuzz.mjs <seed> <count> <out> [more]
import { writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { boxes } from './layout-ref.mjs';

const [seed0, count, out] = [Number(process.argv[2] ?? 1), Number(process.argv[3] ?? 200), process.argv[4] ?? 'bin/ui/fuzz'];
const more = process.argv[5] === 'more';
// (mulberry32)
let seed = seed0;
const rnd = () => {
	seed = (seed + 0x6d2b79f5) | 0;
	let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
	t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
	return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const pick = (a) => a[Math.floor(rnd() * a.length)];
const maybe = (p) => rnd() < p;
const len = () => (maybe(0.2) ? pick(['25%', '50%', '100%']) : Math.round(rnd() * 120));

function node(depth) {
	const s = {};
	if (maybe(0.5)) s.direction = pick(['Row', 'Column', 'RowReverse', 'ColumnReverse']);
	if (maybe(0.2)) s.wrap = true;
	if (maybe(0.3)) s.justify = pick(['Start', 'End', 'Center', 'SpaceBetween', 'SpaceAround', 'SpaceEvenly']);
	if (maybe(0.3)) s.alignItems = pick(['Start', 'End', 'Center', 'Stretch']);
	if (maybe(0.2)) s.alignSelf = pick(['Start', 'End', 'Center', 'Stretch']);
	if (maybe(0.2)) s.alignContent = pick(['Start', 'End', 'Center', 'Stretch', 'SpaceBetween', 'SpaceAround']);
	if (maybe(0.3)) s.grow = pick([0, 1, 2, 0.5]);
	if (maybe(0.2)) s.shrink = pick([0, 1, 3]);
	if (maybe(0.2)) s.basis = len();
	if (maybe(0.5)) s.width = len();
	if (maybe(0.5)) s.height = len();
	if (maybe(0.1)) s.minWidth = len();
	if (maybe(0.1)) s.minHeight = len();
	if (maybe(0.1)) s.maxWidth = len();
	if (maybe(0.1)) s.maxHeight = len();
	if (maybe(0.2)) s.padding = Math.round(rnd() * 10);
	if (maybe(0.2)) s.margin = Math.round(rnd() * 10);
	if (maybe(0.15)) s.borderWidth = Math.round(rnd() * 4);
	if (maybe(0.15)) s.rowGap = Math.round(rnd() * 8);
	if (maybe(0.15)) s.columnGap = Math.round(rnd() * 8);
	if (more) extra(s);
	const n = { style: s };
	if (depth < 3 && maybe(0.7)) n.children = Array.from({ length: 1 + Math.floor(rnd() * 4) }, () => node(depth + 1));
	return n;
}

// ('more': the rest of what Layout lays out)
function extra(s) {
	if (maybe(0.15)) {
		s.display = 'Grid';
		s.gridTemplateColumns = pick(['1fr 1fr', '50px 1fr', 'repeat(3, 1fr)', 'auto 1fr', 'minmax(20px, 1fr) 2fr', '30% auto']);
		if (maybe(0.5)) s.gridAutoRows = pick(['20px', 'auto', '1fr', 'minmax(10px, auto)']);
		if (maybe(0.3)) s.gridTemplateRows = pick(['30px 1fr', 'auto auto', '50% 20px']);
		if (maybe(0.2)) s.gridAutoFlow = pick(['Row', 'Column', 'RowDense']);
		if (maybe(0.2)) s.justifyItems = pick(['Start', 'End', 'Center', 'Stretch']);
	}
	if (maybe(0.1)) s.gridColumn = pick(['span 2', '1 / 3', '2', '-1']);
	if (maybe(0.08)) s.gridRow = pick(['span 2', '1', '2 / 4']);
	if (maybe(0.08)) s.justifySelf = pick(['Start', 'End', 'Center', 'Stretch']);
	if (maybe(0.1)) s.margin = [0, 1, 2, 3].map(() => (maybe(0.4) ? 'auto' : Math.round(rnd() * 8)));
	if (maybe(0.1)) s.order = pick([-1, 1, 2]);
	if (maybe(0.08)) {
		s.position = 'Absolute';
		if (maybe(0.6)) s[pick(['left', 'right'])] = Math.round(rnd() * 40);
		if (maybe(0.6)) s[pick(['top', 'bottom'])] = Math.round(rnd() * 40);
	}
	if (maybe(0.08)) s.aspectRatio = pick([1, 2, 0.5]);
	if (maybe(0.08)) s.overflow = 'Hidden';
	if (maybe(0.04)) s.display = 'None';
}

// (the root is the window: only what lays out its children)
const ROOT = ['direction', 'wrap', 'justify', 'alignItems', 'alignContent', 'padding', 'borderWidth', 'rowGap', 'columnGap'];
const cases = Array.from({ length: count }, (_, i) => {
	const tree = node(0);
	tree.children ??= [node(1)];
	for (const k of Object.keys(tree.style)) if (!ROOT.includes(k)) delete tree.style[k];
	return { name: `fuzz ${seed0}-${i}`, width: 300, height: 200, tree };
});
const { expected, version } = await boxes(cases);
await mkdir(out, { recursive: true });
await writeFile(path.join(out, 'layout-cases.json'), JSON.stringify(cases));
await writeFile(path.join(out, 'layout-expected.json'), JSON.stringify(expected));
console.log(`layout-fuzz.mjs: ${cases.length} trees from seed ${seed0} (chromium ${version}) in ${out}`);
