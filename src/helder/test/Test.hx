package helder.test;

import haxe.PosInfos;
import haxe.coro.Coroutine;
import helder.test.Runner;

// helder.test's API, module-level functions (`import helder.test.Test;`):
// registering tests and hooks, and assertions located by their caller's
// position. No macros. A body is a plain function, or async(coroutine)
// for one on helder.async's loop, with a timeout.
//
//   function tests() {
//     describe("math", () -> {
//       test("adds", () -> equals(1 + 1, 2));
//       test("waits", async(() -> { Async.delay(0.01); assert(true); })).timeout(1);
//     });
//   }

function test(name:String, body:Body):Entry
	return Runner.test(name, body);

// a coroutine as a body (helder.async linked only where one is)
extern inline function async(body:Coroutine<() -> Void>):Body
	return AsyncBody.of(body);

// a group: body registers its tests, hooks and groups (at once)
function describe(name:String, body:() -> Void):Entry
	return Runner.describe(name, body);

// before each test of this group (or file) and its groups, outer ones first
function beforeEach(body:Body)
	Runner.hook(0, body);

// after each test, inner ones first, also after a failure
function afterEach(body:Body)
	Runner.hook(1, body);

// once before the group's first test (a failure leaves its tests out)
function beforeAll(body:Body)
	Runner.hook(2, body);

// once after its last
function afterAll(body:Body)
	Runner.hook(3, body);

// --- assertions: a failure is recorded and the test goes on, except for
// require and fail, which stop it

function assert(cond:Bool, ?msg:String, ?pos:PosInfos) {
	Runner.check();
	if (!cond) Runner.failure(msg ?? "assertion failed", pos);
}

// deeply equal (Equal: arrays, maps, structures, instances, enums, Bytes)
function equals<T>(actual:T, expected:T, ?msg:String, ?pos:PosInfos) {
	Runner.check();
	var at = Equal.diff(actual, expected);
	if (at == null) return;
	var lines = [msg ?? "not equal", '  expected: ${Equal.show(expected)}', '  actual:   ${Equal.show(actual)}'];
	if (at != "") lines.push('  (differing at $at)');
	Runner.failure(lines.join("\n"), pos);
}

function notEquals<T>(actual:T, expected:T, ?msg:String, ?pos:PosInfos) {
	Runner.check();
	if (Equal.diff(actual, expected) == null) Runner.failure((msg ?? "equal, expected a difference") + '\n  both: ${Equal.show(actual)}', pos);
}

// |actual - expected| <= epsilon
function approx(actual:Float, expected:Float, epsilon = 1e-6, ?msg:String, ?pos:PosInfos) {
	Runner.check();
	if (!(Math.abs(actual - expected) <= epsilon))
		Runner.failure('${msg ?? "not within " + epsilon}\n  expected: $expected\n  actual:   $actual', pos);
}

// the error f throws (as thrown: an exception, or a value); a failure if none
function throws(f:() -> Void, ?msg:String, ?pos:PosInfos):Dynamic {
	Runner.check();
	try {
		f();
	} catch (e:Stop) {
		throw e;
	} catch (e:Dynamic) {
		return e;
	}
	Runner.failure(msg ?? "nothing thrown", pos);
	return null;
}

// the same for a coroutine
@:coroutine function throwsAsync(f:Coroutine<() -> Void>, ?msg:String, ?pos:PosInfos):Dynamic {
	Runner.check();
	try {
		f();
	} catch (e:Stop) {
		throw e;
	} catch (e:Dynamic) {
		return e;
	}
	Runner.failure(msg ?? "nothing thrown", pos);
	return null;
}

// v, not null; null stops the test
function require<T>(v:Null<T>, ?msg:String, ?pos:PosInfos):T {
	Runner.check();
	if (v == null) {
		Runner.failure(msg ?? "required a value, got null", pos);
		throw new Stop("required");
	}
	return v;
}

// a failure, the test stopped
function fail(msg:String, ?pos:PosInfos):Dynamic {
	Runner.failure(msg, pos);
	throw new Stop(msg);
}

// value (a String, or shown as a literal) against the snapshot of this
// name in the test file's `.snap` (Foo.test.hx's Foo.test.snap): written
// when missing, rewritten by `helder test -u`
extern inline function snapshot(name:String, value:Dynamic, ?pos:PosInfos)
	Snapshots.check(name, value is String ? value : Equal.show(value), pos);
