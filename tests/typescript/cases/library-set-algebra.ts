{
const a = new Set([1, 2, 3]), b = new Set([3, 2, 4]);
console.log([...a.union(b)], [...a.intersection(b)], [...a.difference(b)], [...a.symmetricDifference(b)]);
console.log(a.isSubsetOf(b), a.isSupersetOf(b), a.isDisjointFrom(b), new Set([2]).isSubsetOf(a), a.isSupersetOf(new Set([2])), a.isDisjointFrom(new Set([5])));
const other = { size: 1, has(v: number) { return v === 2; }, *keys() { yield 2; yield 2; yield 4; yield 4; } };
console.log([...a.intersection(other)], [...a.symmetricDifference(other)], [...a.union(other)]);
const order: string[] = [];
const protocol = { get size() { order.push("size"); return 20; }, get has() { order.push("has"); return (x: number) => x === 2; }, get keys() { order.push("keys"); return function* () { throw "unused"; }; } };
console.log([...a.intersection(protocol)], order.join());
const mutable = new Set([1, 2]); let once = false;
console.log([...mutable.intersection({ size: 10, has(x: number) { if (!once) { once = true; mutable.delete(1); mutable.add(1); mutable.add(3); } return true; }, keys() { throw "unused"; } })]);
let closed = 0;
const early = { size: 1, has() { throw "unused"; }, keys() { return { next() { return { value: 9, done: false }; }, return() { closed++; return {}; } }; } };
console.log(a.isSupersetOf(early as any), closed);
const duplicate = { size: 0, has() { return false; }, *keys() { yield -0; yield 0; yield NaN; yield NaN; } };
const result = new Set<number>().symmetricDifference(duplicate); console.log(result.size, 1 / result.values().next().value!, result.has(NaN));
class Sub extends Set<number> { static get [Symbol.species](): SetConstructor { throw new Error("unused species"); } }
const sub = new Sub([1]); const union = sub.union(new Set([2])); console.log(union instanceof Set, union instanceof Sub, [...union]);
for (const bad of [null, {size: NaN}, {size: -1}, {size: 0, has: 1}, {size: 0, has() {}, keys: 1}]) {
  try { a.union(bad as any); } catch (e: any) { console.log(e.name); }
}
const desc = Object.getOwnPropertyDescriptor(Set.prototype, "union")!;
console.log(desc.writable, desc.enumerable, desc.configurable, Set.prototype.union.length, Set.prototype.union.name);
}
