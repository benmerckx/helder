package helder.test;

import helder.test.Runner;

// helder.test's runner for TypeScript test files (helder/test, its
// index.ts, over helder/test/runner: helder.test.TypeScript): the same
// groups, hooks, filters, snapshots and report as `*.test.hx`'s. Each step
// of a TypeScript test is started with its timeout and calls done once:
// with null, with the error's text, or stopped (require and fail, their
// failure recorded already). Positions are "file:line", the call's, which
// helder's compiler gives each assertion of helder/test (the lowering's
// Definitions).
class Script {
	// a test file's tests follow, its module evaluated (helder test's main
	// imports each one after this call)
	public static function file(path:String)
		Runner.begin(path);

	public static function test(name:String, start:(seconds:Float, done:(error:Null<String>, stopped:Bool) -> Void) -> Void):Entry
		return Runner.test(name, step(start));

	public static function describe(name:String, body:() -> Void):Entry
		return Runner.describe(name, body);

	// beforeEach (0), afterEach (1), beforeAll (2), afterAll (3)
	public static function hook(kind:Int, start:(seconds:Float, done:(error:Null<String>, stopped:Bool) -> Void) -> Void)
		Runner.hook(kind, step(start));

	// an error while the file's tests or a group's are registered
	public static function registering(error:String)
		Runner.registering("error: " + error);

	public static function check()
		Runner.check();

	public static function failure(message:String, at:String)
		Runner.failure(message, pos(at));

	public static function timedOut(seconds:Float)
		Runner.timedOut(seconds);

	// a value's text against the file's snapshot of this name (Foo.test.ts's Foo.test.snap)
	public static function snapshot(name:String, value:String, at:String)
		Snapshots.check(name, value, pos(at));

	public static function run()
		Runner.run();

	static function step(start:(seconds:Float, done:(error:Null<String>, stopped:Bool) -> Void) -> Void):Body
		return Coro((seconds, done) -> start(seconds, (error, stopped) -> {
			if (stopped) Runner.stopped(null) else if (error != null) Runner.stopped("error: " + error);
			done(null);
		}));

	static function pos(at:String):haxe.PosInfos {
		var i = at.lastIndexOf(":");
		var line = i < 0 ? null : Std.parseInt(at.substr(i + 1));
		return {fileName: line == null ? at : at.substr(0, i), lineNumber: line ?? 0, className: "", methodName: ""};
	}
}
