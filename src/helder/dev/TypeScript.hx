package helder.dev;

// helder.dev for TypeScript programs (helder.typescript): keep(key, () =>
// initial), a value kept across a reload under `helder dev`, as a signal
// is (a definition: Slot).
@:typescript("helder/dev")
@:typescript.functions(keep = helder.dev.Slot.keep)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
