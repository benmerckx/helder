// A function called as a value with what its parameters' types exclude
// expect: function-value.ts:3: TSHX100: "1" is not a number
function escaped(n: number): number { return n + 1; }
const call: (n: any) => number = escaped;
console.log(call("1"));
