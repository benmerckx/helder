// `any` from JSON.parse into a number parameter
// expect: parsed-any.ts:4: TSHX100: "ab" is not a number
function twice(n: number): number { return n + n; }
console.log(twice(JSON.parse('"ab"')));
