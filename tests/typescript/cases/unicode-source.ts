// Source positions after non-ASCII text (tsgo reports UTF-16 offsets).
const s = "héllo ☃ 😀";
const r = String.raw`x\ny ☃ ${s} 😀\t`;
const q = String.raw`☃\u0041`;
console.log(r, q, s.length, [...s].length);
