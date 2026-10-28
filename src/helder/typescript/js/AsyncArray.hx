package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Symbols;
import helder.typescript.js.Lib.*;

@:access(helder.typescript.js.Promises)
class AsyncArray {
	public static function setup():Void {
		var ctor:JsObject = Builtins.globals.get("Array");
		ctor.setOwn("fromAsync", Builtins.nativeFunction("fromAsync", 1, (t, a, _) -> from(t, arg(a, 0), arg(a, 1), arg(a, 2))), Attr.HIDDEN);
	}

	static function wait(value:Dynamic, success:Dynamic->Void, failure:Dynamic->Void):Void {
		Promises.then(Promises.resolved(value), Promises.host(v -> {
			try success(v) catch (e:Dynamic) failure(e);}), Promises.host(failure), null);
	}

	static function from(ctor:Dynamic, source:Dynamic, mapper:Dynamic, self:Dynamic):Dynamic {
		var promise = Promises.create(Promises.PromiseProto);
		var out:JsObject = null, it:Dynamic = null, nextFn:Dynamic = null;
		var sync = false, index:Float = 0, length:Float = 0, mapping = mapper != undef(), iterable = false;
		function fail(e:Dynamic):Void Promises.reject(promise, e);
		function finish():Void {
			try {
				put(out, "length", index);
				Promises.resolve(promise, out);
			} catch (e:Dynamic) fail(e);
		}
		function close(error:Dynamic):Void {
			// A pending throw wins over errors from return(), but still awaits it.
			var result:Dynamic;
			try {
				var ret = get(it, "return");
				if (ret == null || ret == undef()) {
					fail(error);
					return;
				}
				result = call(ret, it, []);
				if (sync) {
					if (!isObject(result)) {
						fail(error);
						return;
					}
					result = get(result, "value");
				}
			} catch (_:Dynamic) {
				fail(error);
				return;
			}
			wait(result, _ -> fail(error), _ -> fail(error));
		}
		function store(value:Dynamic, done:() -> Void):Void {
			try {
				Builtins.defineProperty(out, Seed.numberText(index), object(["value", "writable", "enumerable", "configurable"], [value, true, true, true]));
				index++;
				done();
			} catch (e:Dynamic) {
				if (iterable) close(e); else fail(e);
			}
		}
		var pump:() -> Void = null;
		function mapped(value:Dynamic):Void {
			if (!mapping) {
				store(value, pump);
				return;
			}
			var result:Dynamic;
			try result = call(mapper, self, [value, index]) catch (e:Dynamic) {
				if (iterable) close(e); else fail(e);
				return;
			}
			wait(result, v -> store(v, pump), e -> {
				if (iterable) close(e); else fail(e);});
		}
		function asyncResult(result:Dynamic):Void {
			if (!isObject(result)) {
				fail(Builtins.makeError("TypeError", "Iterator result must be an object"));
				return;
			}
			if (Seed.truth(get(result, "done"))) {
				finish();
				return;
			}
			mapped(get(result, "value"));
		}
		pump = function():Void {
			if (!iterable) {
				if (index >= length) {
					finish();
					return;
				}
				var value:Dynamic;
				try value = get(source, index) catch (e:Dynamic) {
					fail(e);
					return;
				}
				wait(value, mapped, fail);
				return;
			}
			if (index >= 9007199254740991.0) {
				close(Builtins.makeError("TypeError", "Array.fromAsync result is too large"));
				return;
			}
			var result:Dynamic;
			try result = call(nextFn, it, []) catch (e:Dynamic) {
				fail(e);
				return;
			}
			if (!sync) {
				wait(result, asyncResult, fail);
				return;
			}
			try {
				if (!isObject(result)) {
					fail(Builtins.makeError("TypeError", "Iterator result must be an object"));
					return;
				}
				var done = Seed.truth(get(result, "done")), value = get(result, "value");
				// Async-from-sync awaits the value even for a completed result.
				var wrapped = Promises.create(Promises.PromiseProto);
				wait(value, v -> Promises.resolve(wrapped, object(["value", "done"], [v, done])), e -> {
					if (done) Promises.reject(wrapped, e); else {
						var ret:Dynamic;
						try {
							ret = get(it, "return");
							if (ret != null && ret != undef()) call(ret, it, []);
						} catch (_:Dynamic) {}
						Promises.reject(wrapped, e);
					}
				});
				wait(wrapped, asyncResult, fail);
			} catch (e:Dynamic) fail(e);
		};
		try {
			if (mapping && !isCallable(mapper)) error("TypeError", "Array.fromAsync mapper must be callable");
			var method = getKey(source, Symbols.asyncIterator, source);
			if (method == null || method == undef()) {
				sync = true;
				method = getKey(source, Symbols.iterator, source);
			}
			if (method != null && method != undef()) {
				if (!isCallable(method)) error("TypeError", "Iterator method must be callable");
				it = call(method, source, []);
				if (!isObject(it)) error("TypeError", "Iterator must be an object");
				nextFn = get(it, "next");
				iterable = true;
				out = isConstructor(ctor) ? construct(ctor, [], ctor) : array([]);
			}
			else {
				source = toObject(source);
				length = Builtins.lengthOf(source);
				if (isConstructor(ctor)) out = construct(ctor, [length], ctor);
				else {
					var created:JsArray = cast array([]);
					setLength(created, length);
					out = created;
				}
			}
			pump();
		} catch (e:Dynamic) fail(e);
		return promise;
	}
}
