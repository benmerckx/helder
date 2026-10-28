// Bindings closures capture (shared boxes) and the rest (plain locals).
function memo(s: TemplateStringsArray) { return s; }
const again = [1, 2].map(() => memo`x`);
console.log(again[0] === again[1]);
function counter() {
	let n = 0, untouched = 10;
	const inc = () => ++n;
	inc(); inc();
	const label = "n";
	const read = () => ({ label, n });
	untouched++;
	return [read(), untouched];
}
console.log(JSON.stringify(counter()));
const fns: Array<() => number> = [];
for (let i = 0; i < 3; i++) fns.push(() => i);
for (const k of [5, 6]) fns.push(() => k);
console.log(fns.map(f => f()).join());
function* steps(from: number, by = 2) { let at = from; while (at < from + 3 * by) { yield at; at += by; } }
console.log([...steps(1)].join(), [...steps(0, 5)].join());
async function delayed(x: number, { y }: { y: number }) { await null; return x + y; }
delayed(1, { y: 2 }).then(v => console.log("async", v));
function hoisted() {
	var late = () => v;
	var v = 3;
	return late();
}
console.log(hoisted());
function shadow(x: number) {
	const outer = x * 2;
	class Box { get value() { return outer; } }
	{ const x = 7; console.log(x, outer); }
	return new Box().value;
}
console.log(shadow(4));
function recur(n: number): number { const go = (k: number): number => k <= 0 ? 0 : k + go(k - 1); return go(n); }
console.log(recur(4));
