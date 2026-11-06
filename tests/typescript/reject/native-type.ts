import { native, i32 } from "helder/native";
// expect: native-type.ts:5: TSHX001: native.c: parameter s's type is not a C type
const libc = native.c({
	fns: {
		strlen: (s: Uint8Array[]): i32 => 0,
	},
});
console.log(libc.strlen([]));
