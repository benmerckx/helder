package helder.async;

// helder.async for TypeScript programs (helder.typescript): a program's
// promises and timers already run on helder.async's loop (its async
// functions as the graph's async computations, DESIGN.md 7.4); these are
// helder.async's own tasks, each a promise to the program (a Task<T> is a
// Promise<T>). Its HTTP client and server are a whole package: their
// coroutines are the program's async functions (helder.typescript.api.Coroutines).
@:typescript("helder/async")
@:typescript.packages(helder.async.http)
@:typescript.functions(delay = helder.async.Tasks.delay, readBytes = helder.async.Tasks.bytes)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
