// A missing argument: undefined where a number is declared
// expect: missing-argument.ts:3: TSHX100: undefined is not a number
function partial(a: number, b: number): number { return a + b; }
console.log((partial as any)(1));
