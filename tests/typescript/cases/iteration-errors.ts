let sum = 0;
for (const value of [1, 2, 3]) sum += value;
let names = "";
for (const key in { x: 1, y: 2 }) names += key;
console.log(sum, names);
function parameter(x: number): number { var x: number; return x; }
console.log(parameter(4));
function defaults(x = 3): number { return x; }
console.log(defaults(), defaults(undefined), defaults(7));
try { throw new TypeError("bad"); } catch (e: any) { console.log(e.name, e.message, e instanceof Error); }
try { new Array(-1); } catch (e: any) { console.log(e instanceof RangeError); }
