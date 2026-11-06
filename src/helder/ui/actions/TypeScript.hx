package helder.ui.actions;

// What helder/ui/actions (src/helder/ui/actions/index.ts) calls of
// helder.ui's actions, for TypeScript programs (helder.typescript):
// helder.ui.actions.Script. A program imports helder/ui/actions, not this module.
@:typescript("helder/ui/actions/runtime", "runtime.d.ts")
@:typescript.classes(helder.ui.actions.Script)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
