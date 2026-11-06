package helder.native;

// What helder/native (src/helder/native/index.ts) does around a C call, for
// TypeScript programs (helder.typescript): helder.native.Script. A program
// imports helder/native, not this module.
@:typescript("helder/native/runtime", "runtime.d.ts")
@:typescript.classes(helder.native.Script)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
