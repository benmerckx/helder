// generators: lazy and infinite sequences, next/throw/return, yield*, finally, iterables, switch and labels
function* range(start: number, end: number, step = 1) { for (let i = start; i < end; i += step) yield i; }
console.log([...range(0, 10, 3)].join(), Array.from(range(1, 4)).map(x => x * x).join());
function* fib() { let [a, b] = [0, 1]; while (true) { yield a; [a, b] = [b, a + b]; } }
const first: number[] = []; for (const f of fib()) { if (f > 50) break; first.push(f); } console.log(first.join());
function* echo(): Generator<string, string, string> { let received = "start"; try { while (true) { received = yield received.toUpperCase(); if (received === "stop") return "stopped"; } } finally { console.log("cleanup"); } }
const e = echo(); console.log(e.next().value, e.next("hello").value, e.next("x").value, JSON.stringify(e.next("stop")), JSON.stringify(e.next()));
const e2 = echo(); e2.next(); console.log(JSON.stringify(e2.return("early")));
function* inner(): Generator<number, string, number> { const x = yield 1; yield x * 2; return "inner-done"; }
function* outer(): Generator<number | string, void, number> { const r = yield* inner(); yield r; yield* [7, 8]; }
const o = outer(); console.log(o.next().value, o.next(5).value, o.next().value, o.next().value, o.next().value, o.next().done);
function* thrower() { try { yield 1; } catch (err) { yield "caught " + err; } yield 3; }
const t = thrower(); console.log(t.next().value, JSON.stringify(t.throw("boom")), t.next().value, t.next().done);
const t2 = thrower(); try { t2.throw("early"); } catch (x) { console.log("thrown", x); }
class Tree { constructor(public value: number, public children: Tree[] = []) {} *[Symbol.iterator](): Generator<number> { yield this.value; for (const c of this.children) yield* c; } }
const tree = new Tree(1, [new Tree(2, [new Tree(3)]), new Tree(4)]); console.log([...tree].join());
const obj = { *items() { yield "a"; yield "b"; } }; console.log([...obj.items()].join(), Object.prototype.toString.call(obj.items()));
function* withArgs(...xs: number[]): Generator<number, void, boolean> { for (const [i, x] of xs.entries()) { const doubled = yield x + i; if (doubled) console.log("got", doubled); } }
const w = withArgs(10, 20); console.log(w.next().value, w.next(true).value, w.next().done);
function* sw(n: number) { switch (n) { case 1: yield "one"; case 2: yield "two"; break; default: yield "other"; } yield "end"; }
console.log([...sw(1)].join(), [...sw(5)].join());
function* labeled() { outer: for (let i = 0; i < 3; i++) { for (let j = 0; j < 3; j++) { if (j === 2) continue outer; if (i === 2) break outer; yield `${i}${j}`; } } }
console.log([...labeled()].join());
const it = range(0, 3); console.log(it[Symbol.iterator]() === it, typeof it.next);
