// What helder/native (src/helder/native/index.ts) does around a C call, for
// TypeScript programs (helder.typescript): helder.native.Script. A program
// imports helder/native, not this module.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {Script: "helder.native.Script", __module: "helder.native.TypeScript"};

// What helder/native's C calls (native.c, a definition: the lowering's
// Natives) do around a call where values cross: a string as a C string, a
// typed array's bytes in C's memory, and back. Addresses are numbers
// (doubles: an address of today's machines fits in their 53 bits), C's
// memory malloc's. A program calls them through helder/native (native.string,
// native.free...), the lowering for a call's arguments.
export declare class Script {
	// s as a NUL-terminated UTF-8 string in C's memory (free it), 0 for null
	static cstring(s: string | null): number;
	// the NUL-terminated UTF-8 string at an address, copied (null for 0)
	static string(at: number): string | null;
	// b's bytes copied into C's memory (free it with back), 0 for null
	static bytesIn(b: Uint8Array | null): number;
	// after the call: what C left at an address bytesIn made copied back into b, the memory freed
	static bytesBack(at: number, b: Uint8Array | null): void;
	// C's memory of malloc's (cstring's, bytesIn's, a C function's) freed
	static free(at: number): void;
	// n bytes at an address, copied
	static bytesAt(at: number, n: number): Uint8Array;
}
