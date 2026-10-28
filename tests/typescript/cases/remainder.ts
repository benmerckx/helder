// Remainders: literal and variable divisors, signs, zeros, fractions and range edges.
function rem(a: number, b: number): number { return a % b; }
const values = [0, -0, 1, -1, 4, -4, 96, 97, 98, 5.5, -5.5, 2147483647, 2147483648, -2147483648, 9007199254740993, 1e300, NaN, Infinity, -Infinity];
let line = "";
for (const v of values) line += String(v % 97) + " " + String(v % 2) + " " + String(v % 1) + " " + String(v % 2147483647) + "|";
console.log(line);
console.log(rem(-4, 2), rem(-0, 5), rem(7, -3), rem(-7, 3), rem(5.5, 1.5), rem(1, 0), rem(0, 0), rem(3, Infinity), rem(-3, -Infinity));
console.log(Object.is(-4 % 2, -0), Object.is(-0 % 97, -0), Object.is(4 % -2, 0), 0.3 % 0.1, 1e17 % 3, -2147483649 % 97);
let acc = 0;
for (let i = -300; i < 300; i += 7) acc += i % 13 + i % 7.5;
console.log(acc);
