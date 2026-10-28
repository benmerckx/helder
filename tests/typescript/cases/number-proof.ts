// Declared `number` bindings that do not always hold numbers must stay dynamic.
function twice(n: number): number { return n + n; }
console.log(twice(2), twice(JSON.parse('"ab"')), twice("x" as unknown as number));
function escaped(n: number): number { return n + 1; }
const call: (n: any) => number = escaped;
console.log(escaped(1), call("1"));
function partial(a: number, b: number): number { return a + b; }
console.log(partial(1, 2), (partial as any)(1));
let total: number = 0;
const append = (value: any) => { total = value; };
append("text");
console.log(total + 1);
function fallsOff(n: number): number { if (n > 0) return n; return n - 1; }
function sum(n: number): number { let s = 0; for (let i = 0; i < n; i++) s += i % 3; return s; }
console.log(fallsOff(3), fallsOff(-1), sum(10), 7 < 10, "7" < "10");
let counter = 0;
counter += 1;
counter++;
const mixed = counter > 1 ? counter : "none";
console.log(counter, mixed, -counter, ~counter);
