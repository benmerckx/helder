// Generic functions (<T>, unconstrained) called with numbers: an array
// filled, reversed through swaps, counted and read, by small helpers.
function fill<T>(n: number, v: T): T[] {
	const out: T[] = [];
	for (let i = 0; i < n; i++) out.push(v);
	return out;
}
function swap<T>(xs: T[], i: number, j: number): void {
	const t = xs[i];
	xs[i] = xs[j];
	xs[j] = t;
}
function reverse<T>(xs: T[]): void {
	const n = xs.length;
	for (let i = 0; i < n / 2 - 0.5; i++) swap(xs, i, n - 1 - i);
}
function count<T>(xs: T[], v: T): number {
	let c = 0;
	for (const x of xs) if (x === v) c++;
	return c;
}
function last<T>(xs: T[]): T {
	return xs[xs.length - 1];
}
const xs = fill(1000, 0);
for (let i = 0; i < xs.length; i++) xs[i] = i % 10;
let total = 0;
for (let round = 0; round < 5000; round++) {
	reverse(xs);
	total += count(xs, round % 10) + last(xs);
}
console.log(total, xs[0], xs[999]);
