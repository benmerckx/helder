package helder.cli;

using StringTools;

// The command line's grammar, one for every command:
//
//   helder <command> [entry] [options]   entry: a .hx file, a directory or a project (default: .)
//   helder <entry>                       shorthand for: helder dev <entry>
//
// The positional is never a target: where a program runs is a flag
// (--target, -d), what is built the positional. The common options
// (--target, -d/--device, -o/--out, --, -h/--help) are parsed here for dev,
// run, build and test, each command's own beside them (dev's --port and
// --host, test's -t, -w, -u and --timeout, inspect's), and the help of
// `helder help` and `helder <command> --help` is written from the same
// table. A usage error is a Usage exception, its message the line printed
// (exit code 2). Pure: no process, no file but `exists` (tests give theirs).
class Options {
	// --target's names for dev, run and build: the platforms, then hxmc's exact targets
	public static final PLATFORMS = ["host", "web", "android", "ios"];
	public static final HXMC_TARGETS = [
		"linux-x86_64", "linux-arm64", "macos-x86_64", "macos-arm64", "windows-x86_64", "windows-arm64", "wasm32-wasi"
	];
	// helder test's
	public static final TEST_TARGETS = ["host", "interp", "wasm"];
	// (test's all: the targets helder ships, interp only when asked: the
	// files that opt in, @:test.interp)
	public static final TEST_ALL = ["host", "wasm"];

	public static final ENTRY = "a .hx file, a directory or a project (default: .)";
	public static final NOT_YET = "not yet: Android and iOS packaging is being moved into helder";

	static final COMMON:Array<Opt> = [
		{
			key: "target",
			names: ["--target"],
			value: "<t>",
			about: "host (default), web, android, ios, or an exact hxmc target (windows-x86_64, macos-arm64, wasm32-wasi, ...)"
		},
		{key: "device", names: ["-d", "--device"], value: "<d>", about: "which phone, emulator or simulator (android, ios); `helder devices` lists them"},
		{key: "out", names: ["-o", "--out"], value: "<path>", about: "build's output"},
		{key: "args", names: ["--"], value: "<args>", about: "the program's arguments (dev, run)"},
	];
	static final HELP:Opt = {key: "help", names: ["-h", "--help"], about: "this help: helder help, or helder <command> --help"};

	public static final COMMANDS:Array<Command> = [
		{
			name: "dev",
			usage: "[entry] [options] [-- <args>]",
			about: "build, run and reload on every change (state kept across a reload)",
			entry: true,
			common: ["target", "device", "args"],
			own: [
				{key: "port", names: ["--port"], value: "<n>", number: true, about: "the HTTP port, the page's and the devtools' (4321, else the next free one)"},
				{key: "host", names: ["--host"], value: "<address>", about: "the address it listens on (127.0.0.1; 0.0.0.0: every interface)"},
			],
		},
		{
			name: "run",
			usage: "[entry] [options] [-- <args>]",
			about: "a release build for this machine, run",
			entry: true,
			common: ["target", "device", "out", "args"],
			own: [],
		},
		{
			name: "build",
			usage: "[entry] [options]",
			about: "a release build: bin/<target>/<name>, its time and size",
			entry: true,
			common: ["target", "device", "out"],
			own: [],
		},
		{
			name: "test",
			usage: "[file or name filter...] [options]",
			about: "build and run the *.test.hx files (helder.test)",
			entry: false,
			common: ["target"],
			targetAbout: "host (default), wasm, all (host and wasm) or interp (the files with @:test.interp); several: host,interp",
			own: [
				{key: "test-name-pattern", names: ["-t", "--test-name-pattern"], value: "<text>", about: "the tests whose name contains it (/text/: a regex)"},
				{key: "watch", names: ["-w", "--watch"], about: "run again on every change (a compilation server's builds)"},
				{key: "update-snapshots", names: ["-u", "--update-snapshots"], about: "rewrite the snapshots that differ"},
				{key: "timeout", names: ["--timeout"], value: "<s>", number: true, about: "seconds an async test may take (5)"},
			],
			notes: [
				"a filter that is part of a test file's path picks those files, any other",
				"one the tests whose name (\"describe > test\") contains it",
			],
		},
		{
			name: "inspect",
			usage: "[dir] [options]",
			about: "a running helder dev's program: its ui tree, state, log or frames",
			entry: false,
			common: [],
			own: [
				{key: "tree", names: ["--tree"], about: "the ui tree (Ui.getTree), once"},
				{key: "state", names: ["--state"], about: "the keys helder.dev.Hot keeps (Runtime.state), once"},
				{key: "log", names: ["--log"], about: "the log, then each entry as it comes (the default)"},
				{key: "frames", names: ["--frames"], about: "the frames' stats, a line per batch"},
				{key: "port", names: ["--port"], value: "<n>", number: true, about: "helder dev's HTTP port (else bin/dev/devtools.json, from dir or here up)"},
			],
		},
		{
			name: "devices",
			usage: "",
			about: "where to run: this machine, a browser, Android devices and emulators, iOS simulators",
			entry: false,
			common: [],
			own: [],
		},
		{
			name: "help",
			usage: "[command]",
			about: "this help, or a command's",
			entry: false,
			common: [],
			own: [],
		},
	];

	public final command:String;
	// the entry (dev, run, build), the filters (test), the directory (inspect)
	public final positionals:Array<String> = [];
	// --target as given (null: host); test's, each of its list (all expanded)
	public var target:Null<String> = null;
	public var targets:Array<String> = ["host"];
	public var device:Null<String> = null;
	public var out:Null<String> = null;
	// after --: null when there was none
	public var programArgs:Null<Array<String>> = null;
	public var help = false;
	// the command's own options, in order, by key (a switch's value "")
	public final own:Array<{key:String, value:String}> = [];

	function new(command:String)
		this.command = command;

	// the entry (dev, run, build)
	public var entry(get, never):Null<String>;

	function get_entry()
		return positionals[0];

	public function has(key:String):Bool
		return Lambda.exists(own, o -> o.key == key);

	// the last value given
	public function value(key:String):Null<String> {
		var v = null;
		for (o in own) if (o.key == key) v = o.value;
		return v;
	}

	public function values(key:String):Array<String>
		return [for (o in own) if (o.key == key) o.value];

	public static function isCommand(word:String):Bool
		return Lambda.exists(COMMANDS, c -> c.name == word);

	// a word --target takes for dev, run or build
	public static function isTarget(word:String):Bool
		return PLATFORMS.contains(word) || HXMC_TARGETS.contains(word);

	// helder's arguments: the command, and its own (the first word a command
	// or an entry: an entry is dev's); `helder`, `-h` and `--help` are help
	public static function route(args:Array<String>, ?exists:String->Bool):{command:String, args:Array<String>} {
		exists ??= p -> sys.FileSystem.exists(p);
		var first = args[0];
		if (first == null || first == "-h" || first == "--help") return {command: "help", args: []};
		if (isCommand(first)) return {command: first, args: args.slice(1)};
		if (first.startsWith("-")) throw new Usage('helder: $first: a command or an entry comes first (helder help)');
		if (exists(first) || first.endsWith(".hx")) return {command: "dev", args: args};
		if (isTarget(first)) throw new Usage('helder: `$first` is a target: use helder dev --target $first');
		throw new Usage('helder: no command or entry $first (commands: ${[for (c in COMMANDS) c.name].join(", ")}; helder help)');
	}

	// a command's arguments; a Usage thrown for a mistake (but with -h or
	// --help: the help asked for, the rest not checked)
	public static function parse(command:String, args:Array<String>, ?exists:String->Bool):Options {
		exists ??= p -> sys.FileSystem.exists(p);
		var c = find(command);
		var o = new Options(command);
		var opts = [for (k in c.common) Lambda.find(COMMON, x -> x.key == k)].concat(c.own).concat([HELP]);
		var i = 0;
		while (i < args.length) {
			var a = args[i++];
			if (a == "--") {
				if (!c.common.contains("args")) throw o.usage("unknown option --", true);
				o.programArgs = args.slice(i);
				break;
			}
			if (!a.startsWith("-") || a == "-") {
				o.positionals.push(a);
				continue;
			}
			var name = a, given:Null<String> = null;
			var eq = a.indexOf("=");
			if (a.startsWith("--") && eq > 0) {
				name = a.substr(0, eq);
				given = a.substr(eq + 1);
			}
			var opt = Lambda.find(opts, x -> x.names.contains(name));
			if (opt == null) throw o.usage('unknown option $name', true);
			var v = "";
			if (opt.value != null) {
				if (given != null) v = given;
				else if (i < args.length && !(args[i] == "--" || Lambda.exists(opts, x -> x.names.contains(args[i])))) v = args[i++];
				else throw o.usage('$name takes a value: $name ${opt.value}', true);
				if (v == "") throw o.usage('$name takes a value: $name ${opt.value}', true);
				if (opt.number == true && !~/^[0-9]+(\.[0-9]+)?$/.match(v)) throw o.usage('$name takes a number, not $v');
			} else if (given != null) throw o.usage('$name takes no value', true);
			switch opt.key {
				case "target": o.target = v;
				case "device": o.device = v;
				case "out": o.out = v;
				case "help": o.help = true;
				case k: o.own.push({key: k, value: v});
			}
		}
		if (!o.help) o.check(c, exists);
		return o;
	}

	function check(c:Command, exists:String->Bool) {
		if (c.entry) {
			if (positionals.length > 1) throw usage('one entry, not ${positionals.join(" and ")}');
			var p = positionals[0];
			if (p != null && isTarget(p) && !exists(p)) throw usage('`$p` is a target: use --target $p');
		} else if (command == "inspect") {
			if (positionals.length > 1) throw usage('one directory, not ${positionals.join(" and ")}');
		} else if (command != "test" && positionals.length > 0) {
			throw usage('unexpected argument ${positionals[0]}', true);
		}
		if (command == "test") {
			if (target != null) {
				targets = target.split(",");
				for (t in targets) if (t != "all" && !TEST_TARGETS.contains(t)) throw usage('no target $t (host, wasm, all, interp; several: host,interp)');
				if (targets.contains("all")) targets = [for (t in TEST_TARGETS) if (TEST_ALL.contains(t) || targets.contains(t)) t];
			}
			return;
		}
		if (target != null) {
			if (target.contains(",")) throw usage('one target, not a list: $target (helder test\'s --target takes several)');
			if (!isTarget(target)) throw usage('no target $target (${PLATFORMS.join(", ")}, or an hxmc target: ${HXMC_TARGETS.join(", ")})');
		}
		var mobile = target == "android" || target == "ios";
		if (device != null && !mobile)
			throw usage('-d/--device picks a phone, emulator or simulator: with --target android or ios (helder devices lists them)');
		if (mobile) throw usage('--target $target: $NOT_YET');
	}

	// a usage error's line: `helder <command>: <message>`, the help named for an option's
	function usage(message:String, ?pointHelp:Bool):Usage
		return new Usage('helder $command: $message' + (pointHelp == true ? ' (helder $command --help)' : ""));

	static function find(command:String):Command {
		var c = Lambda.find(COMMANDS, c -> c.name == command);
		if (c == null) throw new Usage('helder: no command $command (helder help)');
		return c;
	}

	// `helder help` (null) or `helder <command> --help`
	public static function helpText(?command:String):String {
		if (command == null) {
			var out = [
				"helder <command> [entry] [options]",
				"helder <entry>                 shorthand for: helder dev <entry>",
				"",
				'  entry: $ENTRY',
				"",
				"commands:",
			];
			for (c in COMMANDS) out.push("  " + c.name.rpad(" ", 9) + c.about);
			out = out.concat(["", "options:"]);
			var opts = COMMON.concat([HELP]);
			for (o in opts) out.push(line(o, width(opts)));
			out = out.concat([
				"",
				"the commands' own: dev --port, --host; test -t, -w, -u, --timeout (its --target",
				"takes host, wasm, all: both, or interp: the files with @:test.interp, or several:",
				"host,interp); inspect --tree, --state, --log, --frames, --port",
			]);
			return out.join("\n");
		}
		var c = find(command);
		var out = ['helder ${c.name}' + (c.usage == "" ? "" : ' ${c.usage}'), "", '  ${c.about}'];
		if (c.entry) out.push('  entry: $ENTRY');
		if (c.notes != null) out = out.concat([""].concat([for (n in c.notes) '  $n']));
		out = out.concat(["", "options:"]);
		var opts = [];
		for (k in c.common) {
			var o = Lambda.find(COMMON, x -> x.key == k);
			if (k == "target" && c.targetAbout != null) o = {key: o.key, names: o.names, value: o.value, about: c.targetAbout};
			opts.push(o);
		}
		opts = opts.concat(c.own).concat([HELP]);
		for (o in opts) out.push(line(o, width(opts)));
		return out.join("\n");
	}

	// an option's names and value, then what it is (the column at least 19 wide, as the common options')
	static function label(o:Opt):String
		return o.names.join(", ") + (o.value == null ? "" : " " + o.value);

	static function width(opts:Array<Opt>):Int {
		var w = 16;
		for (o in opts) w = Std.int(Math.max(w, label(o).length));
		return w + 3;
	}

	static function line(o:Opt, width:Int):String
		return "  " + label(o).rpad(" ", width) + o.about;
}

typedef Opt = {
	key:String,
	names:Array<String>,
	?value:String,
	?number:Bool,
	about:String,
}

typedef Command = {
	name:String,
	usage:String,
	about:String,
	// the positional an entry (dev, run, build)
	entry:Bool,
	common:Array<String>,
	own:Array<Opt>,
	?targetAbout:String,
	?notes:Array<String>,
}

// a mistake on the command line: its message the line to print (exit code 2)
class Usage extends haxe.Exception {}
