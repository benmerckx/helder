// An `any` assigned to a number binding
// expect: any-assignment.ts:4: TSHX100: "text" is not a number
let total: number = 0;
const append = (value: any) => { total = value; };
append("text");
console.log(total + 1);
