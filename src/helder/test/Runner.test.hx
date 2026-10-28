package helder.test;

import haxe.PosInfos;
import helder.async.Async;
import helder.test.Test;

using StringTools;

// helder.test on itself: assertions (their failures taken back with
// Runner.take), hooks in order, async tests, snapshots; then, natively,
// the program run again on the fixture below (HELDER_TEST_FIXTURE): what
// fails, stops, is skipped, times out or is picked by only, as reported.
function tests() {
	switch Sys.getEnv("HELDER_TEST_FIXTURE") {
		case "1": fixture();
		case "only": fixtureOnly();
		case _: own();
	}
}

private function line(?p:PosInfos):Int
	return p.lineNumber;

private function own() {
	describe("assertions", () -> {
		test("equals: both values, where, the caller's line, and the test goes on", () -> {
			equals({n: 1, list: [{a: "x"}]}, {n: 1, list: [{a: "y"}]}); var at = line();
			equals("same", "same");
			var f = Runner.take();
			equals(f.length, 1);
			equals(f[0].split("\n"), [
				'src/helder/test/Runner.test.hx:$at: not equal',
				'  expected: {list: [{a: "y"}], n: 1}',
				'  actual:   {list: [{a: "x"}], n: 1}',
				"  (differing at .list[0].a)",
			]);
		});
		test("assert, notEquals, approx", () -> {
			assert(1 < 2);
			assert(false, "a message");
			notEquals([1], [2]);
			notEquals([1], [1]);
			approx(0.1 + 0.2, 0.3);
			approx(1.0, 1.1, 0.01);
			var f = [for (s in Runner.take()) s.split("\n")[0]];
			equals(f.length, 3);
			assert(f[0].endsWith(": a message"));
			assert(f[1].endsWith(": equal, expected a difference"));
			assert(f[2].endsWith(": not within 0.01"));
		});
		test("throws returns the error", () -> {
			var e:haxe.Exception = throws(() -> throw new haxe.Exception("boom"));
			equals(e.message, "boom");
			equals(throws(() -> throw "a string"), "a string");
			throws(() -> {});
			equals(Runner.take().length, 1);
		});
		test("throwsAsync", async(() -> {
			var e:haxe.Exception = throwsAsync(() -> {
				Async.delay(0.001);
				throw new haxe.Exception("later");
			});
			equals(e?.message, "later");
		}));
		test("require returns the value", () -> {
			var m = ["a" => 1];
			var v:Int = require(m.get("a"));
			equals(v + 1, 2);
		});
	});

	var log = [];
	describe("hooks", () -> {
		beforeAll(() -> log.push("beforeAll"));
		beforeEach(() -> log.push("before"));
		afterEach(() -> log.push("after"));
		afterAll(() -> log.push("afterAll"));
		test("first", () -> log.push("first"));
		describe("inner", () -> {
			beforeEach(async(() -> {
				Async.delay(0.001);
				log.push("inner before");
			}));
			afterEach(() -> log.push("inner after"));
			test("second", () -> log.push("second"));
		});
	});
	test("hooks ran in order", () -> equals(log, [
		"beforeAll",
		"before", "first", "after",
		"before", "inner before", "second", "inner after", "after",
		"afterAll"
	]));

	describe("async", () -> {
		test("a delay", async(() -> {
			var t0 = haxe.Timer.stamp();
			Async.delay(0.02);
			assert(haxe.Timer.stamp() - t0 >= 0.015);
		}));
		test("its own timeout", async(() -> Async.delay(0.01))).timeout(1);
	});

	test("snapshot", () -> {
		snapshot("text", "two\nlines");
		snapshot("a value", {name: "x", sizes: [1, 2]});
	});

	// (not on wasm32-wasi, which spawns no process)
	#if (hxmc.target != "wasm32-wasi")
	describe("a run of the fixture", () -> {
		test("failures, stops, skips, timeouts", () -> {
			var r = rerun("1");
			equals(r.code, 1, "the exit code");
			var out = r.out;
			function has(s:String, ?pos:PosInfos)
				assert(out.contains(s), 'no "$s" in:\n$out', pos);
			has("src/helder/test/Runner.test.hx:\n");
			has("(pass) fixture > passes [");
			has("(fail) fixture > equals goes on [");
			has("  expected: [1, 3]\n    actual:   [1, 2]\n");
			has(": goes on\n");
			has(": nothing\n");
			has(": by hand\n");
			has("  error: thrown\n");
			has("(skip) fixture > skipped\n");
			has("(fail) fixture > times out [");
			has("  timed out after 0.05 s\n");
			has("(fail) fixture > broken > beforeAll [");
			has(" 1 pass\n 1 skip\n 6 fail\n");
			has("Ran 8 tests across 1 file.");
			assert(!out.contains("not reached"), "require and fail stop the test");
			assert(!out.contains("left out"), "a failed beforeAll leaves its group's tests out");
			assert(~/Runner\.test\.hx:\d+: not equal/.match(out), "the real path, at run time");
		});
		test("only", () -> {
			var r = rerun("only");
			equals(r.code, 0);
			assert(r.out.contains("(pass) fixture > picked ["));
			assert(r.out.contains("(pass) fixture > group > in a picked group ["));
			assert(!r.out.contains("left out"));
			assert(!r.out.contains("tasks >"), "only, across files");
		});
	});
	#end
}

// (the program again, on a fixture: its exit code and output)
private function rerun(fixture:String):{code:Int, out:String} {
	Sys.putEnv("HELDER_TEST_FIXTURE", fixture);
	var p = new sys.io.Process(Sys.programPath(), fixture == "1" ? ["-t", "fixture >"] : []);
	var out = p.stdout.readAll().toString();
	var code = p.exitCode();
	p.close();
	Sys.putEnv("HELDER_TEST_FIXTURE", "");
	return {code: code, out: out};
}

private function fixture() {
	describe("fixture", () -> {
		test("passes", () -> equals(1, 1));
		test("equals goes on", () -> {
			equals([1, 2], [1, 3]);
			assert(false, "goes on");
		});
		test("require stops", () -> {
			require(null, "nothing");
			assert(false, "not reached");
		});
		test("fail stops", () -> {
			fail("by hand");
			assert(false, "not reached");
		});
		test("throws", () -> throw new haxe.Exception("thrown"));
		test("skipped", () -> fail("ran")).skip();
		test("times out", async(() -> Async.delay(1))).timeout(0.05);
		describe("broken", () -> {
			beforeAll(() -> fail("in beforeAll"));
			test("left out", () -> {});
		});
	});
}

private function fixtureOnly() {
	describe("fixture", () -> {
		test("left out", () -> {});
		test("picked", () -> assert(true)).only();
		describe("group", () -> test("in a picked group", () -> {})).only();
	});
}
