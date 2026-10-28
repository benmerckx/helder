// Declared `number` bindings, parameters and results hold F64s.
function twice(n: number): number { return n + n; }
console.log(twice(2), twice(-0), twice(0.5));
function fallsOff(n: number): number { if (n > 0) return n; return n - 1; }
function sum(n: number): number { let s = 0; for (let i = 0; i < n; i++) s += i % 3; return s; }
console.log(fallsOff(3), fallsOff(-1), sum(10), 7 < 10, "7" < "10");
const call: (n: number) => number = twice;
console.log(call(21), [1, 2, 3].map(twice).join());
let counter = 0;
counter += 1;
counter++;
const mixed = counter > 1 ? counter : "none";
console.log(counter, mixed, -counter, ~counter);
