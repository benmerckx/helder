// for loops' counters held as integers where only their step writes them:
// past 2^31, below zero, their remainders (-0 included), as indices, and the
// loops whose counters stay numbers (written in the body, captured).
const big: number[] = [];
for (let i = 2147483645; i < 2147483652; i++) big.push(i, i % 7, i % 1000000007);
console.log(big);
const down: number[] = [];
for (let i = 3; i >= -3; i -= 1) down.push(i, i % 3, i % -2);
for (let i = -2147483645; i >= -2147483652; i--) down.push(i, i % 3, i % 1000000007);
console.log(down, Object.is(down[19], -0));
let count = 0;
for (let i = -5; i <= 5; ++i) for (let j = i + 1; j < 6; j++) count += i % j + j % 4;
console.log(count);
const mods: number[] = [];
for (let i = -4; i < 4; i++) for (let j = -2; j <= 2; j++) mods.push(i % j);
console.log(mods.map(m => Object.is(m, -0) ? "-0" : String(m)).join(" "));
const xs: number[] = [10, 20, 30, 40];
let total = 0;
for (let i = 0; i < xs.length; i++) total += xs[i] * i;
for (let i = xs.length - 1; i >= 0; i--) xs[i] += i;
console.log(total, xs, xs[xs.length]);
for (let i = 0; i < 2.5; i++) console.log("fractional bound", i);
for (let i = 10; i > 0; i--) if (i % 4 === 0) console.log("down", i, i / 4, -i);
// written in the body, captured, stepped by two: numbers as before
for (let i = 0; i < 10; i++) { if (i === 3) i += 0.5; console.log(i); }
const fns: (() => number)[] = [];
for (let c = 0; c < 3; c++) fns.push(() => c);
console.log(fns.map(f => f()));
for (let i = 0; i < 6; i += 2) console.log("by two", i % 4);
let k = 0;
for (let i = 0; i < 5; i++) { k = i; }
console.log(k, typeof k);
outer: for (let i = 0; i < 4; i++) {
	for (let j = 0; j < 4; j++) {
		if (j === 2) continue outer;
		if (i === 3) break outer;
		console.log(i, j, `${i}:${j}`, [i, j], i + "" + j);
	}
}
// charCodeAt at a counter (before, past and at the string's end), bitwise
// operators on numbers (fractions, past 2^32, below -2^31, NaN, Infinity, -0)
const word = "héllo, wörld";
let codes = 0;
for (let i = -2; i <= word.length + 1; i++) codes += isNaN(word.charCodeAt(i)) ? 1000 : word.charCodeAt(i);
console.log(codes);
const bits: number[] = [1.5, -1.5, 2 ** 32 + 3, -(2 ** 31) - 1, NaN, Infinity, -0, 2 ** 31];
const shifted: number[] = [];
for (let i = 0; i < bits.length; i++) shifted.push(bits[i] | 0, bits[i] >>> 1, bits[i] << 2, bits[i] & 6, bits[i] ^ i, i >> 1);
console.log(shifted);
