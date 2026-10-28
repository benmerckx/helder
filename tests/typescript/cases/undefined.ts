function nothing(): void {}
const result = nothing();
console.log(result, typeof nothing(), nothing() === undefined);
console.log(console.log("inner"));
class Empty {}
const empty: number[] = [];
const object = {};
console.log(typeof new Empty(), empty.length, typeof object);
