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
//   id                                          an Objective-C object, a number (a pointer)
//   jstring (string, in native.jni)             a java.lang.String: a string (a new local
//                                               reference for the call; a result's text)
//   Java<"a/b/C">                               a Java object of that class (a reference,
//                                               a number), its descriptor La/b/C;
//
// native.objc({class, lib?, statics?, methods?}): Objective-C's messages to a
// class, each function's key its selector (each _ a colon:
// initWithUTF8String_ is initWithUTF8String:; a quoted key as it is), sent
// through objc_msgSend's address with the signature its annotations give
// (Haxe's helder.os.objc.Msg); statics to the class (objc_getClass), methods
// to their first argument (the receiver, an id); lib a library loaded with
// the program (the framework the class is in); `class` the class's id.
//
//   const NSProcessInfo = native.objc({
//     class: "NSProcessInfo",
//     lib: "/System/Library/Frameworks/Foundation.framework/Foundation",
//     statics: {processInfo: (): id => 0},
//     methods: {processName: (self: id): id => 0},
//   });
//
// native.com({iid, clsid?, base?, methods}): a COM interface, its methods the
// vtable's slots in order after the base's (IUnknown's three: base 3, the
// default; an interface's own after its bases'), each taking the interface's
// pointer first (Haxe's helder.os.win32.Com, VTable); QueryInterface, AddRef
// and Release are its first three; `iid` the IID in C's memory (a pointer);
// with clsid, create() makes an object of the class by the interface
// (CoInitializeEx, CoCreateInstance: a failure thrown with its HRESULT).
// HRESULTs are i32s; an [out] parameter a buffer C fills.
//
// native.jni({class, statics?, methods?, fields?, staticFields?}): a Java
// class through JNIEnv (Android, the activity's main thread; Haxe's
// helder.os.android.Jni): methods take their object first, statics none
// (`new`: a constructor), fields and staticFields are reads (a field's
// function returns its type, taking its object or nothing); each one's JNI
// descriptor from its annotations, its ID found once; a Java exception
// thrown after a call as an error with its text; `class` the class (a
// global reference). Names are the class's binary name: android.os.Build$VERSION.
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
export type id = number;
export type jstring = string | null;
// (a Java object of class C: its reference)
export type Java<C extends string> = number & {readonly __java?: C};

export type Functions = { [name: string]: (...args: any[]) => any };

// (IUnknown's methods, and the IID; create with a clsid)
export type ComObject = {
	QueryInterface(self: pointer, iid: pointer, out: buffer): i32;
	AddRef(self: pointer): u32;
	Release(self: pointer): u32;
	readonly iid: pointer;
	create(): pointer;
};

export const native = {
	// a library's C functions (a definition: its argument static, each
	// function's parameters and result annotated with the types above)
	c<F extends Functions>(def: { lib?: string; fns: F }): F {
		throw new Error("native.c: a definition, compiled by helder's compiler (its argument an object literal)");
	},
	// Objective-C's messages to a class and its objects (a definition)
	objc<S extends Functions = {}, M extends Functions = {}>(def: { class: string; lib?: string; statics?: S; methods?: M }): S & M & { readonly class: id } {
		throw new Error("native.objc: a definition, compiled by helder's compiler (its argument an object literal)");
	},
	// a COM interface's methods by their vtable slots (a definition)
	com<M extends Functions = {}>(def: { iid: string; clsid?: string; base?: number; methods?: M }): M & ComObject {
		throw new Error("native.com: a definition, compiled by helder's compiler (its argument an object literal)");
	},
	// a Java class's methods and fields through JNI (a definition)
	jni<S extends Functions = {}, M extends Functions = {}, F extends Functions = {}, SF extends Functions = {}>(def: { class: string; statics?: S; methods?: M; fields?: F; staticFields?: SF }): S & M & F & SF & { readonly class: pointer } {
		throw new Error("native.jni: a definition, compiled by helder's compiler (its argument an object literal)");
	},
	// the NUL-terminated UTF-8 string at an address, copied (null for 0)
	string(at: pointer): string | null {
		return Script.string(at);
	},
	// n bytes at an address, copied
	bytes(at: pointer, n: number): Uint8Array {
		return Script.bytesAt(at, n);
	},
	// a GUID ("{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}") in C's memory, as
	// Windows lays it out (an IID, a CLSID, a format's): kept, or freed
	guid(text: string): pointer {
		return Script.guid(text);
	},
	// malloc's memory freed (a C function's result the caller owns)
	free(at: pointer): void {
		Script.free(at);
	},
};
