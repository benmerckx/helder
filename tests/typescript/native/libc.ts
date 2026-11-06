// native.c (helder/native): libc's functions called from TypeScript, their
// C signatures from the annotations: a number, a string as a C string, a
// buffer filled by C, a C string returned, a pointer kept and freed.
import { native, i32, u32, usize, cstring, pointer, buffer, f64 } from "helder/native";

const libc = native.c({
	fns: {
		getpid: (): i32 => 0,
		strlen: (s: cstring): usize => 0,
		memset: (b: buffer, c: i32, n: usize): pointer => 0,
		strdup: (s: cstring): pointer => 0,
		strchr: (s: pointer, c: i32): cstring => null,
		atoi(s: string): i32 { return 0; },
		rand: (): u32 => 0,
	},
});
const libm = native.c({ lib: "m", fns: { sqrt: (x: f64): f64 => 0, hypot: (x: number, y: f64): number => 0 } });

console.log(libc.getpid() > 0);
console.log(libc.strlen("hello"), libc.strlen("héllo"), libc.strlen(""));
console.log(libc.atoi("1234"), libc.atoi("-7"));
const bytes = new Uint8Array(6);
libc.memset(bytes, 65, 4);
console.log(Array.from(bytes).join(","));
const copy = libc.strdup("key=value");
console.log(copy !== 0, native.string(copy), libc.strchr(copy, 61));
console.log(Array.from(native.bytes(copy, 3)).join(","));
native.free(copy);
console.log(libm.sqrt(2), libm.hypot(3, 4));
console.log(libc.rand() >= 0);
console.log(typeof libc.getpid, Object.keys(libc).length);
