// Strings loops build piece by piece (buffered while the loop runs).
function plain(n: number): string { let s = "<"; for (let i = 0; i < n; i++) s += i; return s + ">"; }
function nested(): string { let s = ""; for (let i = 0; i < 3; i++) { for (const c of ["a", "b"]) s += c + i; s += ";"; } return s; }
function readInside(): string { let s = ""; for (let i = 0; i < 4; i++) { s += i; if (s.length > 2) s += "!"; } return s; }
function labeled(): string {
	let s = "";
	outer: for (let i = 0; i < 3; i++) {
		for (let j = 0; j < 3; j++) { if (j == 2) continue outer; if (i == 2) break outer; s += `${i}${j} `; }
	}
	return s;
}
function guarded(): string {
	let s = "";
	try { for (let i = 0; i < 5; i++) { s += i; if (i == 3) throw new Error("stop"); } } catch (e) { s += "|caught after " + s.length; }
	return s;
}
function mixed(): string { let s = ""; for (const v of [1, true, null, undefined, 2.5, { toString() { return "o"; } }]) s += v; return s; }
function whileLoop(): string { let s = "", i = 0; while (i < 5) { s += String.fromCharCode(97 + i); i++; } do s += "."; while (s.length < 8); return s; }
console.log(plain(5), nested(), readInside(), labeled(), guarded(), mixed(), whileLoop());
const text = "hello";
let sum = 0;
for (let i = 0; i <= text.length; i++) sum += text.charCodeAt(i) || 0;
console.log(sum, text.charCodeAt(-1), text.charCodeAt(1.7), "".charCodeAt(0));
