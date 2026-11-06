// Generic functions called with numbers run a copy whose T is number; the
// same functions called with other types run as before.
function first<T>(xs: T[]): T { return xs[0]; }
function pair<A, B>(a: A, b: B): [A, B] { return [a, b]; }
function sum<T>(xs: T[], f: (x: T) => number): number {
	let s = 0;
	for (const x of xs) s += f(x);
	return s;
}
function repeat<T>(v: T, n: number): T[] {
	const out: T[] = [];
	for (let i = 0; i < n; i++) out.push(v);
	return out;
}
function swap<T>(xs: T[], i: number, j: number): T[] {
	const t = xs[i];
	xs[i] = xs[j];
	xs[j] = t;
	return xs;
}
function depth<T>(v: T, n: number): T { return n === 0 ? v : depth(v, n - 1); }
function middle<T>(xs: T[]): T { return first(xs.slice(xs.length >> 1)); }
function same<T>(a: T, b: T): boolean { return a === b; }
function grow<T>(xs: T[], v: T): number { xs[xs.length] = v; return xs.length; }

console.log(first([3, 2, 1]), first(["a", "b"]), first<number>([7]), first([[1], [2]]));
console.log(pair(1, 2), pair(1, "x"), pair("x", 1));
console.log(sum([1, 2, 3], x => x * 2), sum(["ab", "c"], s => s.length));
console.log(repeat(1.5, 3), repeat("z", 2), repeat(0, 0));
console.log(swap([1, 2, 3], 0, 2), swap(["a", "b"], 0, 1));
const holes: number[] = [1, 2, 3];
holes[5] = 6;
console.log(swap(holes, 0, 4), holes.length, 4 in holes, 0 in holes);
console.log(depth(5, 10), depth("deep", 3), middle([1, 2, 3, 4, 5]), middle(["p", "q"]));
console.log(same(NaN, NaN), same(0, -0), same(1, 1), same("a", "a"));
const g: number[] = [1];
console.log(grow(g, 2), grow(g, 3), g, grow(["s"], "t"));
const wide: unknown[] = [1, 2];
console.log(first(wide), swap(wide, 0, 1), swap([1, "two", 3] as (number | string)[], 0, 1));
