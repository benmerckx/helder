// Arrays of numbers (number[], branded numbers, T extends number) kept
// unboxed: what JavaScript makes of them, through every path that reads or
// changes one, typed and not.
type Meters = number & { readonly __brand: "meters" };

const xs: number[] = [3, 1, 2];
console.log(xs, xs.length, Array.isArray(xs), typeof xs[0]);

// holes: past the end, a write beyond it, delete
const h: number[] = [1, 2];
h[4] = 5;
console.log(h, h.length, h[3], 3 in h, h[3] === undefined);
let sum = 0;
for (const v of [1, 2, 3]) sum += v;
console.log(sum);
const d: number[] = [1, 2, 3];
delete d[1];
console.log(d, 1 in d, d[1] === undefined);
const out: number[] = [1, 2, 3];
console.log(out[5], out[-1], out[1.5], out[NaN]);
let missing = out[7] + 1;
console.log(missing, out[9] < 3, -out[8]);

// length writes: truncating, growing, appending at the end
const t: number[] = [1, 2, 3, 4, 5];
t.length = 2;
console.log(t, t.length, t[3]);
t.length = 4;
console.log(t, t.length, t[3], 3 in t);
const a: number[] = [];
for (let i = 0; i < 5; i++) a[i] = i * i;
a[a.length] = 99;
console.log(a, a.length);

// methods
const m: number[] = [5, 3, 8, 1];
console.log(m.push(7), m.pop(), m.pop(), m.shift(), m.unshift(0, 9), m);
console.log(m.splice(1, 2, 4, 4, 4), m);
console.log(m.slice(1, 3), m.indexOf(4), m.includes(3), m.join("-"), m.concat([1, 2], 3));
const s: number[] = [10, 9, 1, 100, 25, -3];
s.sort();
console.log(s);
s.sort((x, y) => x - y);
console.log(s, s.toSorted((x, y) => y - x), s.reverse());
console.log(s.map(x => x * 2), s.filter(x => x > 5), s.reduce((p, x) => p + x, 0), s.find(x => x < 0), s.at(-1));
console.log(s.fill(0, 2), [...s], Array.from(s), s.entries().next(), [...s.keys()]);
const p: number[] = [];
p.push(1);
p.push(2.5);
console.log(p, p.pop(), p.pop(), p.pop(), p, p.length);

// branded and constrained element types
const lengths: Meters[] = [];
for (let i = 0; i < 4; i++) lengths.push((i * 1.5) as Meters);
function total<T extends number>(values: T[]): number {
	let r = 0;
	for (const v of values) r += v;
	return r;
}
console.log(lengths, total(lengths), total([1, 2, 3]));

// mixed widening: the same array seen as unknown[] and any
const wide: number[] = [1, 2, 3];
const seen: unknown[] = wide;
seen.push("four");
console.log(wide, wide.length, typeof wide[3]);
const loose: any = [4, 5];
const typed: number[] = loose;
loose.push(null);
console.log(typed, typed.length, typed[2]);
const back: number[] = [1, 2];
(back as any)[1] = "two";
console.log(back, back[0] + 1);
const objs: (number | string)[] = [1, 2];
objs.push("x");
console.log(objs);
function widen(values: unknown[]) { values.push(undefined); values[0] = {}; }
const w: number[] = [7, 8];
widen(w);
console.log(w, w.length);

// JSON, inspection, iteration protocol
const j: number[] = [1.5, -0, 1e21, NaN, Infinity];
console.log(JSON.stringify(j), JSON.parse(JSON.stringify([1, 2, 3])), j);
const parsed: number[] = JSON.parse("[1,2,3]");
parsed.push(4);
console.log(parsed, parsed[3] * 2);
const it = [4, 5][Symbol.iterator]();
console.log(it.next(), it.next(), it.next());
const [first, ...rest] = [1, 2, 3];
console.log(first, rest);
console.log(Object.keys([1, 2]), Object.entries([3]), String([1, 2, 3]), `${[4, 5]}`);
const frozen: number[] = Object.freeze([1, 2]) as number[];
console.log(Object.isFrozen(frozen), frozen);
try { (frozen as number[]).push(3); } catch (e) { console.log((e as Error).name); }

// element arithmetic and copies
const v: number[] = [1, 2, 3];
v[0] += 10;
v[1]++;
--v[2];
const c: number[] = [];
for (let i = 0; i < v.length; i++) c[i] = v[i] * 2;
console.log(v, c, Math.max(v[0], v[1]), v[0] > v[1] ? v[0] : v[1]);
