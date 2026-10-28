// number formatting and parsing, Math
console.log((255).toString(16), (255).toString(2), (-255.5).toString(16), (0.1).toString(3), (1e21).toString(36), Math.PI.toString(7));
console.log((1.005).toFixed(2), (1.45).toFixed(1), (-1.5).toFixed(0), (0).toFixed(2), (1e21).toFixed(2), (123.456).toFixed(10), (0.000001).toFixed(7));
console.log((123.456).toPrecision(4), (0.00001234).toPrecision(2), (123456).toPrecision(2), (1).toPrecision(5), (99.99).toPrecision(3));
console.log((123.456).toExponential(2), (0).toExponential(), (1e-7).toExponential(3), (12345).toExponential(), (-1.5e300).toExponential(1));
console.log(0.1 + 0.2, 1 / 3, 5e-324, 1.7976931348623157e308, 123e-20, 1e21, 1e-7, -0, [-0], 2 ** 53 + 1, 0.000001, 100 / 3);
console.log(Number("0x1F"), Number("  12  "), Number(""), Number("1e3"), Number("0b101"), Number(null), Number([5]), Number("12px"), parseInt("08"), parseFloat(".5e1"), parseInt("123", 5));
console.log(Number.MAX_SAFE_INTEGER, Number.EPSILON > 0, Number.isInteger(5.0), Number.isSafeInteger(2 ** 53), (25).toString(36), Math.round(-0.5), Math.round(2.5), Math.max(), Math.min(1, "2" as any), Math.hypot(3, 4), Math.sign(-3), Math.cbrt(27), Math.log2(8), Math.trunc(-4.7), Math.fround(5.5), Math.clz32(1));
