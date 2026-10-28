// block scoping: functions see later let/const; switch cases share a scope; per-iteration bindings
{ function f() { return x + y; } const x = 1; let y = 2; console.log(f()); }
function outer() { const g = () => later * 2; const later = 21; return g(); } console.log(outer());
function sw(n: number) { switch (n) { case 1: let shared = "s"; default: shared = "d"; console.log(shared); } } sw(1);
const fns: (() => number)[] = []; for (let i = 0; i < 3; i++) { const j = i * 10; fns.push(() => j + i); } console.log(fns.map(f => f()).join());
