// Branded numbers and strings (an intersection with a brand) and type
// parameters constrained to number or string: typed as their primitive
// (Types: an intersection's parts, a type parameter's constraint); other
// intersections and unconstrained parameters stay values.
type Meters = number & { readonly __brand: "meters" };
type Id = string & { readonly __id: true };
type Both = { a: number } & { b: string };

function meters(n: number): Meters { return n as Meters; }
function double(m: Meters): Meters { return (m * 2) as Meters; }
function larger<T extends number>(a: T, b: T): T { return a > b ? a : b; }
function first<T extends string>(xs: T[]): T | undefined { return xs[0]; }
function same<T>(x: T): T { return x; }
function sum<T extends number>(xs: T[]): number {
	let s = 0;
	for (const x of xs) s += x;
	return s;
}
function either(x: Meters | 5): number { return x + 1; }

const ms: Meters[] = [meters(1.5), double(meters(2)), meters(-3)];
console.log(ms, sum(ms), larger(ms[0], ms[1]), larger(3, 2), either(5), either(meters(0.25)));
const id = "user-1" as Id;
console.log(id.length, id.toUpperCase(), first([id, "x" as Id]), first<Id>([]));
const both: Both = { a: 1, b: "two" };
console.log(both, both.a + 1, both.b + "!");
console.log(same(1) + 1, same("s") + "t", same([1, 2]), same(null));
let total: Meters = meters(0);
for (let i = 0; i < 10; i++) total = (total + meters(i)) as Meters;
console.log(total, typeof total, (total as number).toFixed(2));
