package helder.web;

// A WebAssembly module's functions called from JavaScript, typed on both
// sides. A class that implements Exports declares them, as its public
// static functions; the same class is compiled into both programs:
//
//   class LabExports implements helder.web.Exports {
//     public static function invert(data:haxe.io.Bytes):haxe.io.Bytes ...
//     public static function sum(a:Int, b:Int):Int ...
//   }
//
// - In the wasm32-wasi module (hxmc), each becomes callable from
//   JavaScript: a @:hxmc.callback wrapper (the module's way in for
//   JavaScript: docs/plans/lowlevel.md, "WebAssembly") taking its arguments
//   as numbers, and register(), which main calls, names the wrappers to
//   src/helder/web/imports.mjs (host.web.exports).
// - In JavaScript, the class keeps only these functions, each calling the
//   module given to it (LabExports.module = a WasmModule): the arguments
//   converted, bytes and strings copied into the module's memory, the
//   result read back.
//
// The types that cross: Int, Float, Bool, String (UTF-8), haxe.io.Bytes
// (copied in bulk, one copy each way), and Void as a result. Keep such a
// class in a file of its own that imports nothing hxmc-only (its bodies are
// dropped in JavaScript, its imports are not): it calls into the program.
@:autoBuild(helder.web.ExportsMacro.build())
interface Exports {}
