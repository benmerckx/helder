// A value its type does not describe stops the program where it enters a typed slot.
// expect: null-as-number.ts:3: TSHX100: null is not a number
const value = null as unknown as number;
console.log(value + 1);
