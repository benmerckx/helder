package helder.async;

import haxe.Exception;
import helder.test.Test;

function tests() {
	describe("Errors", () -> {
		afterEach(() -> Errors.handler = null);
		test("guard rethrows with no handler", () -> {
			var threw = false;
			try Errors.guard(() -> throw "boom", "frame") catch (e:Exception) threw = true;
			assert(threw);
		});
		test("a handled error goes no further", () -> {
			var got = [];
			Errors.handler = (e, source) -> {
				got.push(source + ": " + e.message);
				true;
			};
			Errors.guard(() -> throw new Exception("boom"), "frame");
			equals(got, ["frame: boom"]);
		});
		test("an error in the handler is not handled", () -> {
			Errors.handler = (_, _) -> throw "again";
			var threw = false;
			try Errors.guard(() -> throw "boom", "event") catch (e:Exception) threw = true;
			assert(threw);
		});
		test("a task's unheard error is reported", () -> {
			var got = [];
			Errors.handler = (e, source) -> {
				got.push(source);
				true;
			};
			Async.launch(_ -> throw new Exception("lost"));
			Loop.current().runUntil(() -> got.length > 0);
			equals(got, ["task"]);
		});
	});
}
