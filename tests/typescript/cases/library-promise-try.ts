{
const order: string[] = [];
const p = Promise.try((a: number, b: number) => { order.push("callback"); return a + b; }, 2, 3);
order.push("after");p.then(v => console.log("try", v, order.join()));
Promise.try(() => { throw new RangeError("bad"); }).catch(e => console.log(e.name, e.message));
Promise.try(null as any).catch(e => console.log("not callable", e.name));
Promise.try(() => ({ then(resolve: (v: number) => void) { resolve(42); } } as any)).then(v => console.log("thenable", v));
class Sub extends Promise<number> {}
const s = Sub.try(() => 7); console.log(s instanceof Sub, s.then(v => v) instanceof Sub);
const cap = Sub.withResolvers(); console.log(cap.promise instanceof Sub); cap.resolve(9);cap.promise.then(v => console.log("cap", v));
const r = Sub.reject("x");console.log(Sub.resolve(s) === s, r instanceof Sub);r.catch(() => {});
// Handle both rejections rather than leaving an unhandled promise in the corpus.
const rejected = Sub.reject("handled");rejected.catch(e => console.log(e));
class Plain extends Promise<number> { static get [Symbol.species]() { return Promise; } }
const plain = new Plain(resolve => resolve(10));const chain = plain.then(v => v + 1); console.log(chain instanceof Plain, chain instanceof Promise);chain.then(v => console.log("species", v));
const fn = Object.getOwnPropertyDescriptor(Promise, Symbol.species)!.get!;
console.log(fn.call(Sub) === Sub, fn.name, Promise.try.length, Promise.try.name);
const f = (Math as any).f16round; console.log([0, -0, 1.00048828125, 1.00146484375, 65519, 65520, 2 ** -25, 3 * 2 ** -25, -(2 ** -26)].map(x => { const v=f(x);return Object.is(v,-0)?"-0":String(v); }).join());
console.log(Reflect[Symbol.toStringTag as never], String.prototype.length, Symbol.dispose.toString(), Symbol.asyncDispose.toString());
}
