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
	// (android: a phone's ABI, arm64, or the device's -d names; ios: an
	// iPhone for build, the simulator for run and dev, which can install
	// only there; ios-sim: the simulator)
	public static final PLATFORMS = ["host", "web", "android", "ios", "ios-sim", "macos"];
	public static final HXMC_TARGETS = [
		"linux-x86_64", "linux-arm64", "macos-x86_64", "macos-arm64", "windows-x86_64", "windows-arm64", "wasm32-wasi", "android-arm64",
		"android-x86_64", "ios-arm64", "ios-sim-arm64"
	];
	// helder test's
	public static final TEST_TARGETS = ["host", "interp", "wasm"];
	// (test's all: the targets helder ships, interp only when asked: the
	// files that opt in, @:test.interp)
	public static final TEST_ALL = ["host", "wasm"];

	public static final ENTRY = "a .hx file, a directory or a project (default: .)";

	// helder run --headless's own (helder.headless, HeadlessCommand)
	public static final HEADLESS:Array<Opt> = [
		{key: "headless", names: ["--headless"], about: "no window: offscreen, on a virtual clock (the options below need it)"},
		{key: "snap", names: ["--snap"], value: "<png>", about: "a frame as a PNG, at --at (several: each --at after its --snap)"},
		{key: "tree", names: ["--tree"], value: "<json>", about: "every node: tag, path, role, label, text, rect, opacity, colours, hover, press, focus, moving"},
		{key: "at", names: ["--at"], value: "<t>", about: "when the --snap or --tree before it is taken (default: end)"},
		{key: "script", names: ["--script"], value: "<json>", about: "timestamped steps: move, down, up, tap, double-click, drag, wheel, key, type, resize, drop, menu-pick, file-dialog, mark, literal"},
		{key: "frames", names: ["--frames"], value: "<n>", number: true, about: "n frames as PNGs into -o/--out (frame_0000.png...) from --start"},
		{key: "every", names: ["--every"], value: "<k>", number: true, about: "--frames: every k-th frame written (1)"},
		{key: "start", names: ["--start"], value: "<t>", about: "where --frames and --video begin (0)"},
		{key: "video", names: ["--video"], value: "<file>", about: "a video (.mp4: H.264; .webm, .mov) of --duration, encoded by ffmpeg"},
		{key: "fps", names: ["--fps"], value: "<n>", number: true, about: "frames a second of the virtual clock (60)"},
		{key: "duration", names: ["--duration"], value: "<s|auto>", about: "--video's length (and -o/--out's without --frames): seconds, or auto (to the end)"},
		{key: "trace", names: ["--trace"], value: "<jsonl>", about: "motion: each tagged node's rect and opacity, a JSON line a frame"},
		{key: "stats", names: ["--stats"], value: "<json>", about: "each frame's work in ms (its events to its end) and GC bytes, its input events, as JSON"},
		{key: "keys", names: ["--keys"], about: "keycaps of the script's keys drawn over the frames"},
		{key: "keys-at", names: ["--keys-at"], value: "<corner>", about: "where: bottom-left (default), bottom, bottom-right, top-left, top, top-right"},
		{key: "keys-theme", names: ["--keys-theme"], value: "<t>", about: "the keycaps' colours: light, dark (default: --theme)"},
		{key: "pointer", names: ["--pointer"], about: "a ripple drawn at each press"},
		{key: "size", names: ["--size"], value: "<WxH>", about: "the window's size in points (the program's)"},
		{key: "scale", names: ["--scale"], value: "<n>", number: true, about: "pixels a point (1)"},
		{key: "theme", names: ["--theme"], value: "<t>", about: "the system's appearance: light (default) or dark"},
		{key: "reduced-motion", names: ["--reduced-motion"], about: "the system asks for reduced motion: transitions jump"},
		{key: "seed", names: ["--seed"], value: "<n>", number: true, about: "Math.random's seed (1)"},
		{key: "dev", names: ["--dev"], about: "a dev build (-D hxmc.dev): its live literals, which the script's literal steps patch"},
	];

	static final COMMON:Array<Opt> = [
		{
			key: "target",
			names: ["--target"],
			value: "<t>",
			about: "host (default), web, android, ios, ios-sim, macos (a universal app bundle), or an exact hxmc target (windows-x86_64, android-x86_64, ...)"
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
				{key: "literals-only-check", names: ["--literals-only-check"], about: "each change's path said, and why: its literals patched (no build) or built"},
				{key: "no-literals", names: ["--no-literals"], about: "every change built, none patched (live literals off: the edit-loop lane's before)"},
			],
		},
		{
			name: "run",
			usage: "[entry] [options] [-- <args>]",
			about: "a release build for this machine, run (--headless: offscreen on a virtual clock, scripted, its frames and tree written)",
			entry: true,
			common: ["target", "device", "out", "args"],
			own: HEADLESS,
			notes: [
				"--headless: the real renderer offscreen (Linux: Mesa's llvmpipe), a frame every 1/fps s of a",
				"virtual clock, Math.random seeded: the same script gives the same bytes; -o/--out is then",
				"--frames' directory (the build: bin/headless/<name>). Times (--at, --start): seconds, end",
				"(the script's end mark, else a second after its last step), mark:<name>, mark:<name>+0.5",
			],
		},
		{
			name: "build",
			usage: "[entry] [options]",
			about: "a release build: bin/<target>/<name>, its time and size",
			entry: true,
			common: ["target", "device", "out"],
			own: [
				{key: "release", names: ["--release"], about: "a release build (what build makes anyway)"},
				{key: "bundle", names: ["--bundle"], about: "android: an App Bundle (.aab) for Google Play, signed by the release key"},
				{
					key: "package",
					names: ["--package"],
					about: "a desktop's release in bin/dist (-o: another directory): macos a signed .app in a zip; windows-* the signed .exe in a zip; linux-* a .tar.gz and a Flatpak manifest"
				}
			],
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
				{key: "tree", names: ["--tree"], about: "the ui tree (Ui.getTree), once, each node with where markup wrote it"},
				{key: "at", names: ["--at"], value: "<file:line[:col]>", about: "the nodes made from that place in the source (Ui.nodesAt), once"},
				{key: "state", names: ["--state"], about: "the keys helder.dev.Hot keeps (Runtime.state), once"},
				{key: "log", names: ["--log"], about: "the log, then each entry as it comes (the default)"},
				{key: "frames", names: ["--frames"], about: "the frames' stats, a line per batch"},
				{key: "port", names: ["--port"], value: "<n>", number: true, about: "helder dev's HTTP port (else bin/dev/devtools.json, from dir or here up)"},
			],
		},
		{
			name: "publish",
			usage: "[entry] [--run | --play | --testflight | --notarize | --screenshots | --listing] [options]",
			about: "a release built, signed and uploaded: helder.run, Google Play's track, TestFlight, or Apple's notary service (none: every destination helder.json names)",
			entry: true,
			common: ["out"],
			own: [
				{key: "run", names: ["--run"], about: "to helder.run: <run.name>.helder.run (helder login, or GitHub Actions' OIDC token)"},
				{key: "play", names: ["--play"], about: "to Google Play (the App Bundle; HELDER_PLAY_SERVICE_ACCOUNT)"},
				{key: "testflight", names: ["--testflight"], about: "to TestFlight (the .ipa; HELDER_ASC_KEY_ID, HELDER_ASC_ISSUER_ID, HELDER_ASC_KEY)"},
				{
					key: "notarize",
					names: ["--notarize"],
					about: "macOS: the release's zip (build --package, a Developer ID's: HELDER_MACOS_*) notarised by Apple (notarytool, the same API key) and stapled"
				},
				{key: "track", names: ["--track"], value: "<t>", about: "Play's track: internal (the default), alpha, beta, production"},
				{key: "draft", names: ["--draft"], about: "Play's release a draft (an app never published)"},
				{key: "dry-run", names: ["--dry-run"], about: "built and signed, what is there read, what would change printed; nothing uploaded"},
				{key: "screenshots", names: ["--screenshots"], about: "the stories with store: true rendered at the stores' sizes, the review sheet (bin/store)"},
				{key: "listing", names: ["--listing"], about: "the stores' listings (--play, --testflight: one; else both): helder.json's listing (the text) and the screenshots, what changed"},
				{key: "submit", names: ["--submit"], about: "--testflight: the build, once processed, on the App Store version and sent for App Review"},
				{key: "locale", names: ["--locale"], value: "<l>", about: "the listing's language (en-US)"},
				{key: "no-screenshot", names: ["--no-screenshot"], about: "--run: no screenshots rendered (the store stories, or one of the program) when helder.json's run.screenshots names none"},
			],
			notes: [
				"with no destination, each one helder.json names: helder.run when it has a run block,",
				"then its targets' publish lists (targets.android.publish: [\"play\"], ...)",
			],
		},
		{
			name: "share",
			usage: "[entry] [options]",
			about: "the web build on helder.run for a week, without an account: a link to send (unlisted)",
			entry: true,
			common: [],
			own: [
				{key: "no-screenshot", names: ["--no-screenshot"], about: "no screenshots rendered for its page (the store stories, or one of the program)"},
				{key: "dry-run", names: ["--dry-run"], about: "built, what would be uploaded printed; nothing uploaded"},
			],
		},
		{
			name: "login",
			usage: "",
			about: "sign in to helder.build with GitHub (for helder publish --run); the token kept in helder's config directory",
			entry: false,
			common: [],
			own: [],
		},
		{
			name: "logout",
			usage: "",
			about: "forget helder login's token",
			entry: false,
			common: [],
			own: [],
		},
		{
			name: "migrate",
			usage: "[dir]",
			about: "helder.webmanifest written as helder.json (the app's settings by target), the old file removed",
			entry: false,
			common: [],
			own: [],
		},
		{
			name: "studio",
			usage: "[project] [options]",
			about: "helder studio on a project: its screens (stories) on a canvas, its code, an inspector, an agent's tools over MCP",
			entry: true,
			common: ["args"],
			own: [
				{key: "mcp-port", names: ["--mcp-port"], value: "<n>", number: true, about: "the MCP server's port on 127.0.0.1 (else HELDER_STUDIO_MCP_PORT, else a free one)"},
			],
			notes: [
				"the project's screens are its stories (*.story.hx, *.story.tsx), \"Flow/Screen\" by name;",
				"all of them run in one dev build, a process of its own (apps/studio/README.md)",
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

	// a target's phone platform: "android", "ios", null for the others
	public static function mobile(target:Null<String>):Null<String>
		return target == null ? null : target.startsWith("android") ? "android" : target.startsWith("ios") ? "ios" : null;

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
		} else if (command == "inspect" || command == "migrate") {
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
		if (command == "run") checkHeadless();
		if (target != null) {
			if (target.contains(",")) throw usage('one target, not a list: $target (helder test\'s --target takes several)');
			if (!isTarget(target)) throw usage('no target $target (${PLATFORMS.join(", ")}, or an hxmc target: ${HXMC_TARGETS.join(", ")})');
		}
		if (device != null && mobile(target) == null)
			throw usage('-d/--device picks a phone, emulator or simulator: with --target android or ios (helder devices lists them)');
		// (an iPhone's app needs a signing identity and a profile: not yet)
		if (target == "ios-arm64" && command != "build")
			throw usage('--target ios-arm64: an iPhone needs a signing identity (not yet); --target ios runs on the simulator');
	}

	// (run's headless options: only with --headless; their values' forms)
	function checkHeadless() {
		var on = has("headless");
		for (o in own)
			if (o.key != "headless" && !on) throw usage('--${o.key}: with --headless', true);
		if (!on) return;
		if (target != null && target != "host") throw usage('--headless: this machine only, not --target $target');
		var size = value("size");
		if (size != null && !~/^[0-9]+x[0-9]+$/.match(size)) throw usage('--size $size: WIDTHxHEIGHT in points (480x560)');
		for (k in ["theme", "keys-theme"]) {
			var t = value(k);
			if (t != null && t != "light" && t != "dark") throw usage('--$k $t: light or dark');
		}
		var c = value("keys-at");
		if (c != null && !["bottom-left", "bottom", "bottom-right", "top-left", "top", "top-right"].contains(c))
			throw usage('--keys-at $c: bottom-left, bottom, bottom-right, top-left, top or top-right');
		for (t in values("at").concat(values("start")))
			if (!isTime(t)) throw usage('$t: a time is seconds, end, mark:<name> or mark:<name>+<seconds>');
		var d = value("duration");
		if (d != null && d != "auto" && !~/^[0-9]+(\.[0-9]+)?$/.match(d)) throw usage('--duration $d: seconds or auto');
		if (has("frames") && out == null) throw usage('--frames: the directory they go to, -o/--out <dir>');
		var v = value("video");
		if (v != null && !(v.endsWith(".mp4") || v.endsWith(".webm") || v.endsWith(".mov"))) throw usage('--video $v: .mp4, .webm or .mov');
		if (has("every") && out == null) throw usage('--every: with --frames and -o/--out');
		if (!has("snap") && !has("tree") && !has("video") && !has("trace") && !has("stats") && out == null)
			throw usage('--headless: what to write: --snap, --tree, --frames with -o, --video, --trace or --stats');
	}

	// a headless run's time: seconds, end, mark:<name>[+-<seconds>]
	public static function isTime(t:String):Bool
		return t == "end" || ~/^[0-9]+(\.[0-9]+)?$/.match(t) || ~/^mark:.+$/.match(t);

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
				"the commands' own: dev --port, --host; run --headless and its (helder run --help);",
				"test -t, -w, -u, --timeout (its --target",
				"takes host, wasm, all: both, or interp: the files with @:test.interp, or several:",
				"host,interp); inspect --tree, --at, --state, --log, --frames, --port",
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
