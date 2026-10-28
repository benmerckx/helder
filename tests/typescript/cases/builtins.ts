// symbols, well-known symbols, iterables, tagged templates, structuredClone, URI functions, collation
{
const s = Symbol("tag"); const t = Symbol.for("shared");
const o: any = { [s]: 1, regular: 2 }; console.log(o[s], Object.keys(o), Object.getOwnPropertySymbols(o).length, s.toString(), s.description, Symbol.for("shared") === t, Symbol.keyFor(t), typeof s);
class Temp { static [Symbol.hasInstance](x: any) { return x === 42; } get [Symbol.toStringTag]() { return "TempTag"; } }
console.log((42 as any) instanceof Temp, Object.prototype.toString.call(new Temp()), String(new Temp()));
const money = { amount: 5, [Symbol.toPrimitive](hint: string) { return hint === "number" ? this.amount : `$${this.amount}`; } };
console.log(+money, `${money}`, money + "", (money as any) * 2);
const iterable = { from: 1, to: 3, [Symbol.iterator]() { let c = this.from, to = this.to; return { next: () => c <= to ? { value: c++, done: false } : { value: undefined, done: true }, [Symbol.iterator]() { return this; } }; } };
console.log([...iterable], Array.from(iterable, (x: any) => x * 10), Math.max(...(iterable as any)));
const tag = (strings: TemplateStringsArray, ...values: unknown[]) => strings.raw.map((r, i) => r + (i < values.length ? `[${values[i]}]` : "")).join("");
console.log(tag`a${1}b${"two"}c\n`, String.raw`x\ty${2}`, ((s: TemplateStringsArray) => s === s)`same`);
function memo(s: TemplateStringsArray) { return s; } const first = memo`x`, again = [1, 2].map(() => memo`x`); console.log(again[0] === again[1], first === again[0], Object.isFrozen(first));
console.log(o, { [Symbol.iterator]: 1, a: Symbol("v") }, [Symbol()]);
}
{
console.log(structuredClone({ a: [1, { b: 2 }], d: new Date(0), m: new Map([[1, 2]]) }));
const big = Array.from({ length: 30 }, (_, i) => i * i); console.log(big);
console.log(Array.from({ length: 3 }), new Array(3), [1, , 3], new Array(5).fill(0), Array.prototype.slice.call({ 0: "a", 1: "b", length: 2 }));
console.log(Object.fromEntries(new Map([["x", 1]])), Object.entries({ a: 1, b: [2] }), Object.assign(Object.create({ inherited: 1 }), { own: 2 }));
const wm = new WeakMap(); const key = {}; wm.set(key, "v"); console.log(wm.get(key), wm.has({}), new WeakSet([key]).has(key));
console.log("%c styled", "color: red", "%i", 42.9, "%j", { a: 1 }, "100%", "%%", "%s", Symbol("s"));
console.log([1, 2, 3].toSorted((a, b) => b - a), [3, 1, 2].toReversed(), [1, 2, 3].with(1, 9), Object.groupBy([1, 2, 3, 4], x => x % 2 ? "odd" : "even"));
console.log("abc".at(-1), "a-b-c".replaceAll("-", "+"), "  x ".trimEnd() + "|", "Ü".normalize("NFD").length >= 1, "abc".localeCompare("abd"), ["b", "a", "C"].sort(), ["b", "a", "C"].sort((a, b) => a.localeCompare(b)));
console.log(encodeURIComponent("a b&c/é"), decodeURIComponent("%E2%82%AC"), encodeURI("http://x.com/a b?q=1&r=é"));
}
