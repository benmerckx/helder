// C functions called from TypeScript: `native.c({lib, fns})`, a definition
// (helder's compiler compiles it with the program: helder.typescript.lower's
// Natives), each function of `fns` an extern of hxmc's (as Haxe's
// `@:hxmc.c @:hxmc.lib(lib) extern class`), its C signature read from its
// annotations; the bodies are never run. The result has the same functions,
// each a call of the C one:
//
//   import { native, i32, usize, cstring } from "helder/native";
//
//   const libc = native.c({
//     fns: {
//       getpid: (): i32 => 0,
//       strlen: (s: cstring): usize => 0,
//     },
//   });
//   console.log(libc.getpid(), libc.strlen("héllo"));   // 6
//
// `lib` is the shared library (kernel32, a framework's path, libm), none for
// libc. A call runs in a safe region, as Haxe's do (the collector may run
// meanwhile). What crosses:
//   i8 u8 i16 u16 i32 u32 i64 u64 isize usize   a number (64-bit ones as doubles)
//   f32 f64 (number)                            a number
//   bool (boolean)                              a boolean
//   cstring (string)                            a string, as a NUL-terminated UTF-8
//                                               copy for the call; a result copied
//   pointer                                     an address, a number (0 is NULL)
//   buffer                                      a Uint8Array's bytes, copied in for
//                                               the call and back after it
//   void                                        no result
import { Script } from "helder/native/runtime";

export type i8 = number;
export type u8 = number;
export type i16 = number;
export type u16 = number;
export type i32 = number;
export type u32 = number;
export type i64 = number;
export type u64 = number;
export type isize = number;
export type usize = number;
export type f32 = number;
export type f64 = number;
export type bool = boolean;
export type cstring = string | null;
export type pointer = number;
export type buffer = Uint8Array;

export type Functions = { [name: string]: (...args: any[]) => any };

export const native = {
	// a library's C functions (a definition: its argument static, each
	// function's parameters and result annotated with the types above)
	c<F extends Functions>(def: { lib?: string; fns: F }): F {
		throw new Error("native.c: a definition, compiled by helder's compiler (its argument an object literal)");
	},
	// the NUL-terminated UTF-8 string at an address, copied (null for 0)
	string(at: pointer): string | null {
		return Script.string(at);
	},
	// n bytes at an address, copied
	bytes(at: pointer, n: number): Uint8Array {
		return Script.bytesAt(at, n);
	},
	// malloc's memory freed (a C function's result the caller owns)
	free(at: pointer): void {
		Script.free(at);
	},
};
