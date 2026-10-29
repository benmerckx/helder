// tests/view's TestRenderer for the TypeScript tests (tests/typescript/helder):
// a tree of nodes written out as HTML. A program's own Haxe classes declared
// to it as helder's are: a module's declaration class (helder.typescript.api.Modules),
// its declarations generated (tests/typescript/run.mjs checks them).
@:typescript("./test-renderer", "../typescript/helder/test-renderer.d.ts")
@:typescript.classes(TestRenderer.TestNode)
@:build(helder.typescript.api.Manifest.build())
class TestTypeScript {}
