class Base {
    value: number = 4;
    describe(): string { return "base:" + this.value; }
}
class Derived extends Base {
    extra: number = 3;
    describe(): string { return "derived:" + (this.value + this.extra); }
}
function show(x: Base): string { return x.describe(); }
const item = new Derived();
console.log(show(item), item instanceof Base, item instanceof Derived);
class Counter {
    value: number = 0;
    constructor(start: number) { this.value = start; }
    add(n: number): number { this.value = this.value + n; return this.value; }
}
const c = new Counter(5);
console.log(c.add(2), c.add(3));
