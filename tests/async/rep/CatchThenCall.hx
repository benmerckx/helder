import haxe.coro.*;
import haxe.coro.continuations.FunctionContinuation;
import haxe.coro.context.Context;

// An issue of the coroutine transform (hxmc's compiler; Eval, JavaScript and
// hxmc alike): a coroutine catches an error that resumed it, then calls a
// coroutine that returns at once; the state after that call checks the
// continuation's `error` again, still the caught one, and throws it.
//   haxe -main CatchThenCall --interp   (-cp tests/async/rep)
// prints "result null error x"; expected "result after: 1 error null".
// helder.async's suspending functions clear it (Async.stale); a coroutine of
// the program's own that returns at once is still affected.
class CatchThenCall {
	static var later:Array<Void->Void> = [];

	@:coroutine(transformed)
	static function failsLater(completion:IContinuation<Int>):SuspensionResult<Int> {
		later.push(() -> completion.resume(null, new haxe.Exception("x")));
		return cast SuspensionResult.suspended;
	}

	@:coroutine(transformed)
	static function now(completion:IContinuation<Any>):SuspensionResult<Int>
		return SuspensionResult.withResult(1);

	@:coroutine static function body():String {
		try failsLater() catch (e:haxe.Exception) trace("caught");
		var n = now();
		return "after: " + n;
	}

	static function main() {
		var c:Coroutine<() -> String> = body;
		c(new FunctionContinuation(Context.empty, (r, e) -> trace("result", r, "error", e)));
		while (later.length > 0) later.shift()();
	}
}
