// A headless Ui for the TypeScript tests (tests/typescript/helder/ui.tsx):
// UiProbe, the root it gives a ui Node (opaque, helder.ui's renderer's).
@:typescript("./ui-probe", "../typescript/helder/ui-probe.d.ts")
@:typescript.types(helder.ui.Node)
@:typescript.classes(UiProbe)
@:build(helder.typescript.api.Manifest.build())
class UiTypeScript {}
