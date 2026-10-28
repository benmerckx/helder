// classes: statics, private members, accessors, super, built-in subclasses, call/apply/bind, console.log formatting
class Counter { static instances = 0; static #secret = 42; #count = 0; readonly label: string;
  constructor(label = "c") { this.label = label; Counter.instances++; }
  get count() { return this.#count; } increment() { this.#count++; return this; }
  static reveal() { return Counter.#secret; } #hidden() { return "h" + this.#count; } peek() { return this.#hidden(); }
  static { Counter.instances = 100; } has(o: object) { return #count in o; } }
const c = new Counter().increment().increment();
console.log(c.count, Counter.instances, Counter.reveal(), c.peek(), c.has(c), c.has({}), c.label);
class Animal { constructor(public name: string) {} speak() { return `${this.name} makes a sound`; } toString() { return `Animal(${this.name})`; } }
class Dog extends Animal { constructor(name: string, private breed: string) { super(name); } speak() { return super.speak() + " (woof)"; } get info() { return `${this.name}/${this.breed}`; } }
const d = new Dog("Rex", "lab"); console.log(d.speak(), d.info, `${d}`, d instanceof Animal, Object.getPrototypeOf(d) === Dog.prototype, Dog.name, typeof Dog);
class ValidationError extends Error { constructor(message: string, public field: string) { super(message); this.name = "ValidationError"; } }
try { throw new ValidationError("bad", "email"); } catch (e) { if (e instanceof ValidationError) console.log(e.name, e.message, e.field, e instanceof Error, String(e)); }
class Stack<T> extends Array<T> { peek() { return this[this.length - 1]; } }
const s = new Stack<number>(); s.push(1, 2, 3); console.log(s.peek(), s.length, Array.isArray(s), s instanceof Stack);
class Registry extends Map<string, number> { total() { let t = 0; for (const v of this.values()) t += v; return t; } }
const r = new Registry([["a", 1], ["b", 2]]); console.log(r.total(), r.size, r.get("b"));
const methods = { greet(this: { who: string }) { return "hi " + this.who; }, who: "you" };
const greet = methods.greet; console.log(methods.greet(), greet.call({ who: "them" }), greet.apply({ who: "all" }, []), greet.bind({ who: "bound" })());
function Legacy(this: any, v: number) { this.v = v; } Legacy.prototype.double = function () { return this.v * 2; };
const l = new (Legacy as any)(21); console.log(l.double(), l instanceof (Legacy as any));
const o = { a: 1, get b() { return this.a + 1; }, set b(v: number) { this.a = v; }, ["c" + 1]: 3, toString() { return "O"; } };
o.b = 10; console.log(o.a, o.b, o.c1, `${o}`, Object.keys(o).join());
console.log([1, [2, [3, [4]]]], { x: { y: { z: { w: 1 } } } }, new Map([[1, { a: 1 }]]), new Set(["a"]), [undefined, null, -0, , 5], { "key-with-dash": 1, f() {}, g: () => 1, h: class K {} });
console.log("%s is %d years and %o", "Bob", 42.9, { a: [1] }, "extra");
const frozen = Object.freeze({ q: 1 }); try { (frozen as any).q = 2; } catch (e: any) { console.log(e instanceof TypeError); }
console.log(Object.getOwnPropertyNames(Counter.prototype).join(), JSON.stringify(d), Object.entries(new Dog("a", "b")).join("|"));
