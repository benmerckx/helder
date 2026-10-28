function identity(x: any): any { return x; }
console.log(typeof undefined, typeof null, typeof true, typeof 4, typeof "x");
console.log(identity(NaN) === identity(NaN), identity(0) === identity(-0));
console.log(identity("2") == identity(2), identity("2") === identity(2));
console.log(identity("") == identity(0), identity("bad") == identity(0));
console.log(identity(false) || "fallback", identity("") ? "bad" : "empty");
console.log(0xff, 0b101, 0o77, 1_000);
console.log(1e-7, 1e-6, 1e20, 1e21, 1.2345678901234567, "" + -0);
console.log(identity("1x") == identity(1), identity("1e") == identity(1));
console.log(identity(" 0b10 ") == identity(2), identity("0x10") == identity(16), identity("0o10") == identity(8));
console.log(identity("\u00a0\ufeff") == identity(0), identity("-0") === identity(0));
