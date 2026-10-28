package helder.cli;

import helder.async.Async;
import helder.cli.Options.Usage;

// The helder command, a native program on helder.async (its processes,
// sockets and file watching):
//
//   helder <command> [entry] [options]
//   helder <entry>                        shorthand for: helder dev <entry>
//
// the grammar and the help Options'. Built from this checkout by `bun run
// helder` (bin/cli/helder, when a source changed).
class Cli {
	static function main() {
		var o = try {
			var r = Options.route(Sys.args());
			if (r.command == "help") {
				if (r.args.length > 1 || (r.args.length == 1 && !Options.isCommand(r.args[0])))
					throw new Usage('helder help: no command ${r.args.join(" ")} (helder help)');
				Sys.println(Options.helpText(r.args[0]));
				Sys.exit(0);
			}
			Options.parse(r.command, r.args);
		} catch (e:Usage) {
			Sys.stderr().writeString(e.message + "\n");
			Sys.exit(2);
			null;
		}
		if (o.help) {
			Sys.println(Options.helpText(o.command));
			Sys.exit(0);
		}
		switch o.command {
			case "build":
				Async.main(_ -> Sys.exit(BuildCommand.run(o, false)));
			case "run":
				Async.main(_ -> Sys.exit(BuildCommand.run(o, true)));
			case "dev":
				Async.main(task -> Sys.exit(DevCommand.run(task, o)));
			case "test":
				Async.main(task -> Sys.exit(TestCommand.run(task, o)));
			case "inspect":
				Async.main(task -> Sys.exit(Inspect.run(task, o)));
			case "devices":
				Async.main(_ -> Sys.exit(Devices.run(o)));
			case c:
				Sys.stderr().writeString('helder: no command $c (helder help)\n');
				Sys.exit(2);
		}
	}
}
