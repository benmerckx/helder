package helder.test;

import haxe.PosInfos;

using StringTools;

// What helder.test registers and runs: groups (a test file's, describe's)
// of tests and hooks, run in order, then a summary in bun's style; exit
// code 1 on a failure. The runner `helder test` generates calls `add` for
// each file and `run`:
//
//   Runner.add("src/Foo.test.hx", "bin/test/src/Foo_test.hx", Foo_test.tests);
//   Runner.run();
//
// Its arguments: -t <text> (each one in the test's full name, "describe >
// test"; /text/ a regex, given Runner.regex), -n <text> (any one in it),
// -u (snapshots rewritten), --timeout <seconds>.
//
// A test's steps are its ancestors' beforeEach hooks (outer first), its
// body, then their afterEach hooks (inner first, also after a failure);
// beforeAll and afterAll around a group's tests. Each step is a plain
// function or a coroutine (helder.async's loop, AsyncBody), so the run is
// a sequence of steps each calling the next when done: in the browser's
// loop, where nothing waits, too.
class Runner {
	// seconds an async step may take, unless a test or group says otherwise
	public static var timeout = 5.0;

	static final root = new Group(null, "");
	static var group:Group = root;
	static var current:Null<Case>;
	static var checks = 0;
	// linked path => real path (PosInfos' and stacks' file names)
	static final paths = new Map<String, String>();
	static final steps:Array<(next:() -> Void) -> Void> = [];
	static var step = 0;
	// (each -t's test; any -n's)
	static final patterns:Array<String->Bool> = [];
	static final names:Array<String> = [];
	// a /regex/ pattern's test: set by a runner that wants one (EReg is
	// linked only then)
	public static var regex:Null<String->(String->Bool)>;
	static var counts = {pass: 0, fail: 0, skip: 0, files: 0};
	static var t0 = 0.0;
	@:allow(helder.test) static var update = false;
	@:allow(helder.test) static final atEnd:Array<() -> Void> = [];

	// a test file: tests() registers its tests (its own group)
	public static function add(real:String, linked:String, tests:() -> Void) {
		paths.set(linked, real);
		var g = new Group(root, real);
		g.file = real;
		group = g;
		try tests() catch (e:haxe.Exception) {
			var c = new Case(g, "(registering)", Sync(() -> {}));
			c.failures.push(error(e));
		}
		group = root;
	}

	public static function run(?args:Array<String>) {
		args ??= Sys.args();
		var i = 0;
		while (i < args.length) {
			switch args[i++] {
				case "-t":
					var p = args[i++];
					if (p.length > 2 && p.startsWith("/") && p.endsWith("/") && regex != null) patterns.push(regex(p.substr(1, p.length - 2)))
					else patterns.push(s -> s.contains(p));
				case "-n": names.push(args[i++]);
				case "-u": update = true;
				case "--timeout": timeout = Std.parseFloat(args[i++]);
				case a: Sys.println('helder.test: unknown argument $a');
			}
		}
		t0 = Sys.time();
		var only = hasOnly(root);
		for (g in root.items)
			plan(cast g, only);
		pump();
	}

	// (the next steps, as long as each is done when it returns)
	static function pump() {
		while (step < steps.length) {
			var s = steps[step++];
			var done = false, waiting = false;
			s(() -> {
				done = true;
				if (waiting) pump();
			});
			if (!done) {
				waiting = true;
				return;
			}
		}
		finish();
	}

	// --- registering

	@:allow(helder.test) static function test(name:String, body:Body):Entry
		return new Case(group, name, body);

	@:allow(helder.test) static function describe(name:String, body:() -> Void):Entry {
		var g = new Group(group, name), outer = group;
		group = g;
		try body() catch (e:haxe.Exception) {
			var c = new Case(g, "(registering)", Sync(() -> {}));
			c.failures.push(error(e));
		}
		group = outer;
		return g;
	}

	@:allow(helder.test) static function hook(kind:Int, body:Body)
		switch kind {
			case 0: group.beforeEach.push(body);
			case 1: group.afterEach.push(body);
			case 2: group.beforeAll.push(body);
			case _: group.afterAll.push(body);
		}

	// --- planning

	static function hasOnly(g:Group):Bool {
		for (e in g.items) if (e.mode == 2 || (e is Group && hasOnly(cast e))) return true;
		return false;
	}

	// (whether a case runs: skipped, filtered out (null) or run)
	static function runs(c:Case, only:Bool):Null<Bool> {
		var e:Entry = c, marked = false;
		while (e != null) {
			if (e.mode == 1) return false;
			if (e.mode == 2) marked = true;
			e = e.parent;
		}
		if (c.failures.length > 0) return true;
		if (only && !marked) return null;
		var n = c.fullName();
		for (p in patterns) if (!p(n)) return null;
		if (names.length > 0 && !Lambda.exists(names, s -> n.contains(s))) return null;
		return true;
	}

	static function count(g:Group, only:Bool):Int {
		var n = 0;
		for (e in g.items) n += e is Group ? count(cast e, only) : (runs(cast e, only) != null ? 1 : 0);
		return n;
	}

	static function plan(g:Group, only:Bool) {
		if (count(g, only) == 0) return;
		if (g.file != null) steps.push(next -> {
			counts.files++;
			Sys.println('\n${g.file}:');
			next();
		});
		for (h in g.beforeAll) groupHook(g, "beforeAll", h);
		for (e in g.items) {
			if (e is Group) {
				plan(cast e, only);
				continue;
			}
			var c:Case = cast e;
			switch runs(c, only) {
				case null:
				case false: steps.push(next -> {
						counts.skip++;
						Sys.println('(skip) ${c.fullName()}');
						next();
					});
				case true: planCase(c);
			}
		}
		for (h in g.afterAll) groupHook(g, "afterAll", h);
	}

	static function planCase(c:Case) {
		var chain = [], g = c.parent;
		while (g != null) {
			chain.unshift(g);
			g = g.parent;
		}
		steps.push(next -> {
			current = c;
			c.start = Sys.time();
			next();
		});
		var seconds = c.seconds();
		for (g in chain) for (h in g.beforeEach)
			steps.push(next -> c.stopped || c.broken() ? next() : exec(h, seconds, next));
		steps.push(next -> c.stopped || c.broken() ? next() : exec(c.body, seconds, next));
		chain.reverse();
		for (g in chain) for (h in g.afterEach)
			steps.push(next -> c.broken() ? next() : exec(h, seconds, next));
		steps.push(next -> {
			current = null;
			if (!c.broken()) report(c);
			next();
		});
	}

	// (beforeAll and afterAll: reported only when they fail; a failed
	// beforeAll leaves its group's tests out)
	static function groupHook(g:Group, what:String, h:Body)
		steps.push(next -> {
			if (g.broken) return next();
			var c = new Case(null, what, h);
			c.parent = g;
			current = c;
			c.start = Sys.time();
			exec(h, c.seconds(), () -> {
				current = null;
				if (c.failures.length > 0) {
					report(c);
					if (what == "beforeAll") g.broken = true;
				}
				next();
			});
		});

	static function exec(b:Step, seconds:Float, next:() -> Void)
		switch b {
			case Sync(f):
				try f() catch (e:haxe.Exception) thrown(e);
				next();
			case Coro(start):
				start(seconds, e -> {
					if (e != null) thrown(e);
					next();
				});
		}

	// --- failures

	@:allow(helder.test) static function check()
		checks++;

	// a failure of the running test (or of the file's registration)
	@:allow(helder.test) static function failure(message:String, pos:PosInfos) {
		var f = '${file(pos.fileName)}:${pos.lineNumber}: $message';
		if (current != null) current.failures.push(f) else {
			var c = new Case(group, "(registering)", Sync(() -> {}));
			c.failures.push(f);
		}
	}

	// (an error a step threw: a Stop is a failure already recorded)
	@:allow(helder.test) static function thrown(e:haxe.Exception) {
		if (current == null) return;
		current.stopped = true;
		if (!(e is Stop)) current.failures.push(error(e));
	}

	@:allow(helder.test) static function timedOut(seconds:Float)
		if (current != null) {
			current.stopped = true;
			current.failures.push('timed out after $seconds s');
		}

	static function error(x:haxe.Exception):String {
		var out = ['error: ${x.message}'];
		// (the frames above the runner's, at most five)
		for (s in x.stack) switch s {
			case FilePos(_, f, line, _):
				if (f.endsWith("helder/test/Runner.hx") || f.endsWith("helder/test/AsyncBody.hx") || out.length > 5) break;
				out.push('  at ${file(f)}:$line');
			case _:
		}
		return out.join("\n");
	}

	// a compiled file's name as the user wrote it (a linked test file's real path)
	@:allow(helder.test) static function file(f:String):String {
		var r = paths.get(f);
		if (r != null) return r;
		for (l => r in paths)
			if (f.endsWith("/" + l) || f.endsWith("\\" + l)) return r;
		return f;
	}

	// --- reporting

	static function report(c:Case) {
		var t = ms(Sys.time() - c.start);
		if (c.failures.length == 0) {
			counts.pass++;
			Sys.println('(pass) ${c.fullName()} [$t]');
			return;
		}
		counts.fail++;
		Sys.println('(fail) ${c.fullName()} [$t]');
		for (f in c.failures) Sys.println("  " + f.split("\n").join("\n  "));
	}

	static function finish() {
		for (f in atEnd) f();
		var total = counts.pass + counts.fail + counts.skip;
		Sys.println("");
		Sys.println(' ${counts.pass} pass');
		if (counts.skip > 0) Sys.println(' ${counts.skip} skip');
		Sys.println(' ${counts.fail} fail');
		Sys.println(' $checks check' + (checks == 1 ? "" : "s"));
		Sys.println('Ran $total tests across ${counts.files} file${counts.files == 1 ? "" : "s"}. [${ms(Sys.time() - t0)}]');
		Sys.exit(counts.fail > 0 ? 1 : 0);
	}

	@:allow(helder.test) static function running():Null<Case>
		return current;

	// the running test's failures so far, taken out (helder.test's own tests
	// check them)
	@:allow(helder.test) static function take():Array<String> {
		var f = current?.failures.copy() ?? [];
		if (current != null) current.failures.resize(0);
		return f;
	}

	// milliseconds, two decimals
	static function ms(seconds:Float):String {
		var c = Math.round(seconds * 100000);
		var frac = Std.string(c % 100);
		return Std.int(c / 100) + "." + (frac.length < 2 ? "0" + frac : frac) + "ms";
	}
}

// a step: a plain function, or a coroutine started on helder.async's loop
// (AsyncBody), given its timeout, calling done once with its error or null
enum Step {
	Sync(f:() -> Void);
	Coro(start:(seconds:Float, done:(error:Null<haxe.Exception>) -> Void) -> Void);
}

// a test's or a hook's body: a plain function, or async(coroutine)
abstract Body(Step) from Step to Step {
	@:from static inline function plain(f:() -> Void):Body
		return Sync(f);
}

// a test or a group, as registered: marked skipped, only, or with a timeout
class Entry {
	public final name:String;
	@:allow(helder.test) var parent:Null<Group>;
	@:allow(helder.test) var mode = 0;
	@:allow(helder.test) var limit:Null<Float>;

	function new(parent:Null<Group>, name:String) {
		this.parent = parent;
		this.name = name;
		if (parent != null) parent.items.push(this);
	}

	// left out (reported as skipped)
	public function skip():Entry {
		mode = 1;
		return this;
	}

	// run with the others marked only, the rest left out
	public function only():Entry {
		mode = 2;
		return this;
	}

	// seconds each async step may take (a group's: each of its tests')
	public function timeout(seconds:Float):Entry {
		limit = seconds;
		return this;
	}

	// "describe > test", without the file
	public function fullName():String {
		var names = [name], p = parent;
		while (p != null && p.file == null && p.parent != null) {
			names.unshift(p.name);
			p = p.parent;
		}
		return names.join(" > ");
	}
}

@:allow(helder.test)
class Group extends Entry {
	final items:Array<Entry> = [];
	final beforeEach:Array<Body> = [];
	final afterEach:Array<Body> = [];
	final beforeAll:Array<Body> = [];
	final afterAll:Array<Body> = [];
	var file:Null<String>;
	var broken = false;

	public function new(parent, name)
		super(parent, name);
}

@:allow(helder.test)
class Case extends Entry {
	final body:Body;
	final failures:Array<String> = [];
	var start = 0.0;
	var stopped = false;

	public function new(parent, name, body) {
		super(parent, name);
		this.body = body;
	}

	function seconds():Float {
		var e:Entry = this;
		while (e != null) {
			if (e.limit != null) return e.limit;
			e = e.parent;
		}
		return Runner.timeout;
	}

	// (under a group whose beforeAll failed)
	function broken():Bool {
		var g = parent;
		while (g != null) {
			if (g.broken) return true;
			g = g.parent;
		}
		return false;
	}
}

// thrown by require and fail: the test stops, its failure recorded
class Stop extends haxe.Exception {}
