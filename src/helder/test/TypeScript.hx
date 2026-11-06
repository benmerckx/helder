package helder.test;

// helder.test's runner for TypeScript programs (helder.typescript): what
// helder/test (src/helder/test/index.ts: test, describe, the hooks, the
// assertions, snapshots) registers and reports through, the runner of
// `*.test.hx` (helder.test.Script). A program imports helder/test, not
// this module.
@:typescript("helder/test/runner", "runner.d.ts")
@:typescript.classes(helder.test.Script, helder.test.Runner.Entry)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
