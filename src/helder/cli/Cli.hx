package helder.cli;

import helder.async.Async;

// The helder command, a native program on helder.async (its processes,
// sockets and file watching): `helder <command> [args...]`. Built from this
// checkout by `bun run helder` (bin/cli/helder, when a source changed).
class Cli {
	static final commands = [
		{name: "test", about: "build and run the *.test.hx files (helder.test)"},
	];

	static function main() {
		var args = Sys.args();
		switch args.shift() {
			case "test":
				Async.main(_ -> Sys.exit(TestCommand.run(args)));
			case null | "help" | "-h" | "--help":
				Sys.println("helder <command> [args...]\n");
				for (c in commands) Sys.println('  ${StringTools.rpad(c.name, " ", 8)} ${c.about}');
			case c:
				Sys.println('helder: no command $c (helder help)');
				Sys.exit(2);
		}
	}
}
