package helder.jobs;

// helder.jobs for TypeScript programs (helder.typescript): job(f), a
// module-level function of the program run on a worker, its input, its
// result and the constants it reads Sendable (a definition: checked and
// compiled with the program, as Haxe's Jobs.job); run(input) a promise of
// its result.
@:typescript("helder/jobs")
@:typescript.classes(helder.jobs.script.Job)
@:typescript.functions(job = helder.jobs.script.Job.of)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
