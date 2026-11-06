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
	// the word (a pointer, 8 bytes) at index of the words at an address: a
	// vtable's entry (native.com's and native.jni's methods: the function at
	// a slot of an object's table, word(word(object, 0), slot))
	static word(at: number, index: number): number;
	// a GUID ("{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}") in C's memory, its 16
	// bytes as Windows lays them out, kept for the process (native.com's IIDs
	// and CLSIDs)
	static guid(text: string): number;
	// a COM object of the class clsid, by its interface iid (native.com's
	// create: CoInitializeEx once, apartment-threaded, then CoCreateInstance
	// in process or local; a failure thrown with its HRESULT)
	static comCreate(clsid: number, iid: number): number;
	// JNI (native.jni; Android): the calling thread's JNIEnv (the program's
	// thread attached to the activity's VM: ScriptJni)
	static jniEnv(): number;
	// a class by its name (android/os/Build$VERSION), a global reference
	// kept for the process
	static jniClass(name: string): number;
	// a method's ID (kind 0: an instance's, 1: a static one) or a field's
	// (2: an instance's, 3: a static one) by its name and JNI descriptor; a
	// missing one thrown
	static jniMember(cls: number, name: string, descriptor: string, kind: number): number;
	// the arguments of the next JNI call (jvalue[16]): argument i set (kind:
	// 0 an integer or a reference, 1 a jfloat, 2 a jdouble, 3 a jboolean)
	static jniArg(i: number, kind: number, v: number): void;
	// the address of those arguments
	static jniArgs(): number;
	// after a JNI call: a pending Java exception thrown (its text), cleared
	static jniCheck(): void;
	// a java.lang.String of s (a local reference; 0 for null)
	static jniString(s: string | null): number;
	// a java.lang.String's text (null for 0), its local reference deleted
	static jniText(at: number): string | null;
}
