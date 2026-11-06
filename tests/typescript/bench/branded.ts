// Branded numbers (number & {__brand}) and generics over numbers (T extends
// number): units through small functions in a hot loop, as typed as plain
// numbers.
type Meters = number & { readonly __brand: "meters" };
type Seconds = number & { readonly __brand: "seconds" };

function meters(n: number): Meters { return n as Meters; }
function seconds(n: number): Seconds { return n as Seconds; }
function speed(d: Meters, t: Seconds): number { return d / t; }
function larger<T extends number>(a: T, b: T): T { return a > b ? a : b; }
function total<T extends number>(xs: T[]): number {
	let s = 0;
	for (const x of xs) s += x;
	return s;
}

const distances: Meters[] = [];
for (let i = 0; i < 1000; i++) distances.push(meters(i % 13 + 1));
let best = 0, sum = 0;
for (let round = 0; round < 5000; round++) {
	for (let i = 0; i < distances.length; i++) {
		const v = speed(distances[i], seconds(round % 7 + 1));
		best = larger(best, v);
	}
	sum += total(distances);
}
console.log(best, sum);
