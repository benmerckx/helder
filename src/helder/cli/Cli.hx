package helder.cli;

import helder.async.Async;

// The helder command, a native program on helder.async (its processes,
// sockets and file watching): `helder <command> [args...]`. Built from this
// checkout by `bun run helder` (bin/cli/helder, when a source changed).
class Cli {
	static final commands = [
		{name: "dev", about: "build, run and reload on every change: this machine, or web (a page)"},
		{name: "build", about: "a release build: bin/<target>/<name>, its time and size"},
		{name: "run", about: "a release build for this machine, run"},
		{name: "test", about: "build and run the *.test.hx files (helder.test)"},
	];

	static function main() {
		var args = Sys.args();
		switch args.shift() {
			case "build":
				Async.main(_ -> Sys.exit(BuildCommand.run(args, false)));
			case "run":
				Async.main(_ -> Sys.exit(BuildCommand.run(args, true)));
			case "dev":
				Async.main(task -> Sys.exit(DevCommand.run(task, args)));
			case "test":
				Async.main(_ -> Sys.exit(TestCommand.run(args)));
			case null | "help" | "-h" | "--help":
				Sys.println("helder <command> [args...]\nhelder [target] <entry>: dev's\n");
				for (c in commands) Sys.println('  ${StringTools.rpad(c.name, " ", 8)} ${c.about}');
			// (no command, an entry or a target: helder examples/todo/Todo.hx is dev's)
			case c if (StringTools.endsWith(c, ".hx") || c == "web" || c == "host" || sys.FileSystem.exists(c)):
				args.unshift(c);
				Async.main(task -> Sys.exit(DevCommand.run(task, args)));
			case c:
				Sys.println('helder: no command $c (helder help)');
				Sys.exit(2);
		}
	}
}
