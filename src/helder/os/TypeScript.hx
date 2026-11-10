package helder.os;

// helder.os for TypeScript programs (helder.typescript): what an app keeps
// between runs (Store), the program's arguments and environment (args(),
// env(name): Sys's). Its windows, events and App are helder/scene's.
@:typescript("helder/os")
@:typescript.classes(helder.os.Store)
@:typescript.functions(args = Sys.args, env = Sys.getEnv)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
