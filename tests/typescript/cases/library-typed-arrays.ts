// Typed arrays over ArrayBuffers: each kind's conversions, views sharing
// bytes, the prototype's methods, iteration, inspection.
const u8 = new Uint8Array([1, 2, 255, 256, -1, 3.7]);
console.log(u8, u8.length, u8.byteLength, u8.BYTES_PER_ELEMENT, Uint8Array.BYTES_PER_ELEMENT);
const c8 = new Uint8ClampedArray([-5, 0.5, 1.5, 2.5, 254.6, 300, NaN]);
console.log(c8);
const i8 = Int8Array.of(127, 128, -129, 200);
console.log(i8, i8[1], i8[10], i8[-1]);
const i16 = new Int16Array(3);
i16[0] = 40000;
i16[1] = -1;
i16[2] = 3.9;
console.log(i16, new Uint16Array(i16));
const i32 = new Int32Array([2147483648, -2147483649, 7]);
const u32 = new Uint32Array([-1, 4294967296, 5]);
console.log(i32, u32);
const f32 = new Float32Array([0.1, 1 / 3, 1e40, -0]);
const f64 = new Float64Array([0.1, 1 / 3, 1e40]);
console.log(f32, f64);

// views of one buffer
const buffer = new ArrayBuffer(16);
const bytes = new Uint8Array(buffer);
const words = new Uint32Array(buffer, 4, 2);
const view = new DataView(buffer);
words[0] = 0x01020304;
view.setFloat64(8, 1.5, true);
console.log(bytes, words.length, words.byteOffset, words.buffer === buffer, ArrayBuffer.isView(words), ArrayBuffer.isView(buffer));
const sub = bytes.subarray(4, 8);
sub[0] = 99;
console.log(sub, bytes[4], sub.buffer === buffer, sub.byteOffset);
const copy = bytes.slice(4, 8);
copy[0] = 1;
console.log(copy, bytes[4]);

// methods
const a = new Float64Array([5, 1, 4, 2, 3]);
console.log(a.at(-1), a.indexOf(4), a.lastIndexOf(9), a.includes(2), a.join("-"), String(a));
console.log(a.map(x => x * 2), a.filter(x => x > 2), a.reduce((s, x) => s + x, 0), a.reduceRight((s, x) => s + "" + x, ""));
console.log(a.find(x => x > 3), a.findIndex(x => x > 3), a.findLast(x => x < 3), a.findLastIndex(x => x < 3), a.some(x => x > 4), a.every(x => x > 0));
console.log(a.toSorted(), a.toReversed(), a.with(0, 9), a);
console.log(new Float64Array([10, 9, 1, NaN, -0, 0]).sort(), new Int32Array([3, 1, 2]).sort((x, y) => y - x));
const filled = new Int16Array(6).fill(7, 1, 4);
filled.set([1, 2], 4);
filled.set(new Int8Array([-3]), 0);
console.log(filled, filled.copyWithin(0, 3), filled.reverse());
let total = 0;
for (const x of new Uint8Array([1, 2, 3])) total += x;
console.log(total, [...new Int8Array([4, -5])], Array.from(new Uint16Array([6, 7])), [...new Uint8Array([8, 9]).entries()], [...new Uint8Array(2).keys()]);
new Uint8Array([1, 2]).forEach((x, i) => console.log("each", x, i));
console.log(Object.keys(new Uint8Array(3)), JSON.stringify(new Uint8Array([1, 2])), Object.prototype.toString.call(new Float32Array(1)));
console.log(Uint8Array.from([1, 2, 3], x => x * 10), Float32Array.from("123"));
console.log(new Uint8Array(150));

// errors
try {
	new Uint32Array(new ArrayBuffer(6));
} catch (e) {
	console.log((e as Error).name);
}
try {
	new Uint16Array(new ArrayBuffer(8), 1);
} catch (e) {
	console.log((e as Error).name);
}
