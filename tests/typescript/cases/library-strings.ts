const s = "  Hello😀  ";
console.log(s.trim(), s.trimStart().length, s.trimEnd().length);
console.log("abc".slice(-2), "abc".substring(2, 0), "😀".codePointAt(0), "x".charCodeAt(3));
console.log("abcabc".includes("bc", 2), "abc".startsWith("b", 1), "abc".endsWith("b", 2));
console.log("a,b,c".split(",", 2).join("|"), "x".repeat(3), "1".padStart(3, "0"));
console.log("abcabc".replace("b", "[$&]"), "aa".replaceAll("a", "b"));
console.log(String.fromCodePoint(0x1f600), String.fromCharCode(65, 66));
console.log(Math.abs(-4), Math.floor(1.9), Math.trunc(-1.9), Math.max(1, 9, 2));
console.log(Number.isNaN(NaN), Number.isFinite("4"), parseInt("-0xff!", 0), parseFloat("1.2e2x"));
