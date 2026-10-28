let value = 1;
function change(): number { value = 9; return 2; }
console.log(value + change(), value);
let calls = 0;
function tick(): number { calls = calls + 1; return calls; }
console.log(false && tick(), true || tick(), calls);
function nil(): number | null { return null; }
console.log(0 ? tick() : 4, nil() ?? tick());
