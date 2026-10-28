package helder.cli;

import helder.cli.Options.Usage;
import helder.test.Test;

// the command line's grammar (Options): the shorthand, the positional never
// a target, --target, -d, --, the options' errors, the help; and helder
// devices' parsing of adb's and simctl's lists
function tests() {
	// (a file system: these paths exist)
	final files = ["examples/todo/Todo.hx", "examples/todo", "web-app"];
	final exists = (p:String) -> files.contains(p);
	final parse = (command:String, args:Array<String>) -> Options.parse(command, args, exists);
	final route = (args:Array<String>) -> Options.route(args, exists);
	final usage = (f:() -> Void) -> {
		var e = throws(f);
		return e is Usage ? (e : Usage).message : 'not a Usage: $e';
	};

	describe("route", () -> {
		test("a command", () -> {
			equals(route(["build", "examples/todo"]), {command: "build", args: ["examples/todo"]});
			equals(route(["devices"]), {command: "devices", args: []});
		});
		test("nothing, -h and --help: help", () -> {
			equals(route([]).command, "help");
			equals(route(["-h"]).command, "help");
			equals(route(["--help"]).command, "help");
			equals(route(["help", "build"]), {command: "help", args: ["build"]});
		});
		test("an entry first: dev's shorthand", () -> {
			equals(route(["examples/todo/Todo.hx"]), {command: "dev", args: ["examples/todo/Todo.hx"]});
			equals(route(["examples/todo", "--target", "web"]), {command: "dev", args: ["examples/todo", "--target", "web"]});
			// (a .hx file that is not there: dev says so)
			equals(route(["Missing.hx"]).command, "dev");
			// (a directory named like a target is an entry)
			equals(route(["web-app"]).command, "dev");
		});
		test("a target first", () -> {
			equals(usage(() -> route(["web", "examples/todo"])), "helder: `web` is a target: use helder dev --target web");
			equals(usage(() -> route(["android"])), "helder: `android` is a target: use helder dev --target android");
		});
		test("neither", () -> {
			assert(usage(() -> route(["biuld"])).indexOf("helder: no command or entry biuld (commands: dev, run, build") == 0);
			equals(usage(() -> route(["--target", "web"])), "helder: --target: a command or an entry comes first (helder help)");
		});
	});

	describe("the entry", () -> {
		test("one, the default none", () -> {
			equals(parse("build", []).entry, null);
			equals(parse("dev", ["examples/todo/Todo.hx"]).entry, "examples/todo/Todo.hx");
			equals(usage(() -> parse("build", ["a", "b"])), "helder build: one entry, not a and b");
		});
		test("never a target", () -> {
			for (c in ["dev", "run", "build"])
				equals(usage(() -> parse(c, ["web", "examples/todo"])), 'helder $c: one entry, not web and examples/todo');
			equals(usage(() -> parse("dev", ["web"])), "helder dev: `web` is a target: use --target web");
			equals(usage(() -> parse("build", ["windows-x86_64"])), "helder build: `windows-x86_64` is a target: use --target windows-x86_64");
			equals(usage(() -> parse("run", ["host"])), "helder run: `host` is a target: use --target host");
		});
		test("a path named like a target is a path", () -> {
			var files = ["web"];
			equals(Options.parse("build", ["web"], p -> files.contains(p)).entry, "web");
		});
	});

	describe("--target", () -> {
		test("host by default, one value", () -> {
			equals(parse("build", []).target, null);
			equals(parse("build", ["--target", "web"]).target, "web");
			equals(parse("build", ["--target=wasm32-wasi"]).target, "wasm32-wasi");
			equals(parse("dev", ["examples/todo", "--target", "host"]).target, "host");
			equals(parse("build", ["--target", "macos-arm64", "examples/todo"]).entry, "examples/todo");
		});
		test("no short form", () -> {
			equals(usage(() -> parse("build", ["-t", "web"])), "helder build: unknown option -t (helder build --help)");
		});
		test("its mistakes", () -> {
			equals(usage(() -> parse("build", ["--target"])), "helder build: --target takes a value: --target <t> (helder build --help)");
			equals(usage(() -> parse("build", ["--target", "-o", "x"])), "helder build: --target takes a value: --target <t> (helder build --help)");
			assert(usage(() -> parse("build", ["--target", "wasm"])).indexOf("helder build: no target wasm (host, web, android, ios, or an hxmc target: linux-x86_64") == 0);
			equals(usage(() -> parse("dev", ["--target", "web,host"])), "helder dev: one target, not a list: web,host (helder test's --target takes several)");
		});
		test("android and ios: not yet", () -> {
			for (c in ["dev", "run", "build"]) for (t in ["android", "ios"])
				equals(usage(() -> parse(c, ["--target", t])), 'helder $c: --target $t: not yet: Android and iOS packaging is being moved into helder');
		});
		test("helder test's: a list", () -> {
			equals(parse("test", []).targets, ["host"]);
			equals(parse("test", ["--target", "host,wasm"]).targets, ["host", "wasm"]);
			equals(parse("test", ["--target", "all"]).targets, ["host", "interp", "wasm"]);
			equals(usage(() -> parse("test", ["--target", "web"])), "helder test: no target web (host, interp, wasm, all; several: host,wasm)");
		});
	});

	describe("-d, --device", () -> {
		test("parsed", () -> {
			// (checked against the target after the loop: here --help, which skips the check)
			equals(parse("dev", ["-d", "emulator-5554", "--help"]).device, "emulator-5554");
			equals(parse("build", ["--device=iPhone", "-h"]).device, "iPhone");
		});
		test("for android and ios only", () -> {
			for (c in ["dev", "run", "build"]) {
				equals(usage(() -> parse(c, ["-d", "emulator-5554"])), 'helder $c: -d/--device picks a phone, emulator or simulator: with --target android or ios (helder devices lists them)');
				equals(usage(() -> parse(c, ["--target", "web", "--device", "x"])), 'helder $c: -d/--device picks a phone, emulator or simulator: with --target android or ios (helder devices lists them)');
			}
			equals(usage(() -> parse("dev", ["--target", "android", "-d", "emulator-5554"])), "helder dev: --target android: not yet: Android and iOS packaging is being moved into helder");
		});
		test("a value", () -> {
			equals(usage(() -> parse("run", ["-d"])), "helder run: -d takes a value: -d <d> (helder run --help)");
		});
		test("not test's, inspect's or devices'", () -> {
			equals(usage(() -> parse("test", ["-d", "x"])), "helder test: unknown option -d (helder test --help)");
			equals(usage(() -> parse("devices", ["-d", "x"])), "helder devices: unknown option -d (helder devices --help)");
		});
	});

	describe("--", () -> {
		test("the program's arguments (dev, run)", () -> {
			var o = parse("run", ["examples/todo", "--", "3", "--target", "-h"]);
			equals(o.programArgs, ["3", "--target", "-h"]);
			equals(o.target, null);
			assert(!o.help);
			equals(parse("dev", ["--"]).programArgs, []);
			equals(parse("dev", []).programArgs, null);
		});
		test("not build's or test's", () -> {
			equals(usage(() -> parse("build", ["--", "x"])), "helder build: unknown option -- (helder build --help)");
			equals(usage(() -> parse("test", ["--"])), "helder test: unknown option -- (helder test --help)");
		});
	});

	describe("-o, --out", () -> {
		test("build's and run's", () -> {
			equals(parse("build", ["-o", "bin/x"]).out, "bin/x");
			equals(parse("run", ["--out", "bin/x", "examples/todo"]).out, "bin/x");
			equals(usage(() -> parse("dev", ["-o", "x"])), "helder dev: unknown option -o (helder dev --help)");
		});
	});

	describe("the commands' own", () -> {
		test("dev's", () -> {
			var o = parse("dev", ["--port", "0", "--host", "0.0.0.0", "examples/todo"]);
			equals(o.value("port"), "0");
			equals(o.value("host"), "0.0.0.0");
			equals(usage(() -> parse("dev", ["--port", "x"])), "helder dev: --port takes a number, not x");
			equals(usage(() -> parse("build", ["--port", "1"])), "helder build: unknown option --port (helder build --help)");
		});
		test("test's", () -> {
			var o = parse("test", ["geom", "-t", "length", "-w", "-u", "--timeout", "2", "--test-name-pattern", "/a.b/", "src/x"]);
			equals(o.positionals, ["geom", "src/x"]);
			equals(o.values("test-name-pattern"), ["length", "/a.b/"]);
			assert(o.has("watch") && o.has("update-snapshots"));
			equals(o.value("timeout"), "2");
			equals(usage(() -> parse("test", ["-t"])), "helder test: -t takes a value: -t <text> (helder test --help)");
		});
		test("inspect's", () -> {
			var o = parse("inspect", ["--tree", "--port", "4321", "app"]);
			assert(o.has("tree") && !o.has("log"));
			equals(o.value("port"), "4321");
			equals(o.positionals, ["app"]);
			equals(usage(() -> parse("inspect", ["--target", "web"])), "helder inspect: unknown option --target (helder inspect --help)");
		});
		test("a switch takes no value", () -> {
			equals(usage(() -> parse("test", ["--watch=1"])), "helder test: --watch takes no value (helder test --help)");
		});
	});

	describe("unknown options", () -> {
		test("one format in every command", () -> {
			for (c in ["dev", "run", "build", "test", "inspect", "devices"])
				equals(usage(() -> parse(c, ["--bogus"])), 'helder $c: unknown option --bogus (helder $c --help)');
		});
	});

	describe("help", () -> {
		test("-h and --help anywhere, the rest unchecked", () -> {
			assert(parse("build", ["web", "--help"]).help);
			assert(parse("test", ["-h"]).help);
		});
		test("the same names and wording", () -> {
			var all = Options.helpText();
			assert(all.indexOf("helder <entry>") >= 0);
			for (c in ["dev", "run", "build", "test", "inspect", "devices", "help"]) assert(all.indexOf('\n  $c ') >= 0, c);
			var target = "--target <t>", rest = "host (default), web, android, ios, or an exact hxmc target (windows-x86_64, macos-arm64, wasm32-wasi, ...)";
			for (c in ["dev", "run", "build"]) {
				var h = Options.helpText(c);
				assert(h.indexOf('helder $c [entry]') == 0, c);
				for (t in [all, h]) {
					assert(~/  --target <t> +host \(default\), web, android, ios, or an exact hxmc target/.match(t), c);
					assert(~/  -d, --device <d> +which phone, emulator or simulator \(android, ios\); `helder devices` lists them/.match(t), c);
					assert(~/  -h, --help +this help/.match(t), c);
				}
			}
			assert(~/  -o, --out <path> +build's output/.match(Options.helpText("build")));
			assert(~/  -- <args> +the program's arguments \(dev, run\)/.match(Options.helpText("dev")));
			assert(Options.helpText("dev").indexOf("--port <n>") >= 0);
			assert(Options.helpText("build").indexOf("--port") < 0);
			assert(Options.helpText("build").indexOf("-- <args>") < 0);
		});
	});

	describe("devices", () -> {
		test("adb devices -l", () -> {
			var text = [
				"* daemon not running; starting now at tcp:5037",
				"* daemon started successfully",
				"List of devices attached",
				"emulator-5554          device product:sdk_gphone64_x86_64 model:sdk_gphone64_x86_64 device:emu64xa transport_id:1",
				"R58M12ABCDE            unauthorized usb:1-1 transport_id:2",
				"",
			].join("\n");
			equals(DeviceList.adbDevices(text), [
				{id: "emulator-5554", name: "sdk gphone64 x86 64", kind: "emulator", target: "android"},
				{id: "R58M12ABCDE", name: "R58M12ABCDE (unauthorized)", kind: "device", target: "android"},
			]);
			equals(DeviceList.adbDevices("List of devices attached\n\n"), []);
		});
		test("xcrun simctl list devices available", () -> {
			var text = [
				"== Devices ==",
				"-- iOS 17.2 --",
				"    iPhone 15 (8A9C6B4E-6E2B-4A43-9C7B-2C7B1E9D5F11) (Shutdown) ",
				"    iPad Air (5th generation) (1B2C3D4E-5F60-4718-8293-A4B5C6D7E8F9) (Booted) ",
				"-- watchOS 10.2 --",
				"    Apple Watch Series 9 (45mm) (0A1B2C3D-4E5F-4061-8273-94A5B6C7D8E9) (Shutdown) ",
			].join("\n");
			equals(DeviceList.simulators(text), [
				{id: "8A9C6B4E-6E2B-4A43-9C7B-2C7B1E9D5F11", name: "iPhone 15 (iOS 17.2)", kind: "simulator", target: "ios"},
				{id: "1B2C3D4E-5F60-4718-8293-A4B5C6D7E8F9", name: "iPad Air (5th generation) (iOS 17.2)", kind: "simulator, booted", target: "ios"},
			]);
		});
		test("the table", () -> {
			equals(DeviceList.table([{id: "host", name: "this machine", kind: "host", target: "linux-x86_64"}]),
				"id    name          kind  target\nhost  this machine  host  linux-x86_64");
		});
	});
}
