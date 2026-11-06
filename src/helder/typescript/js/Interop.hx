package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Buffers;

// Values crossing between a TypeScript program and helder's Haxe API, where
// the compiled program calls it (helder.typescript.lower.Haxe: the
// manifest's types say what each Haxe function takes and gives): a
// JavaScript value into what Haxe takes untyped (toHaxe: arrays, functions
// and plain objects made Haxe's), or checked into a type (int, string,
// instance, reader...); a Haxe value back (toJs). Haxe objects (a View, a
// node) pass as they are, opaque to the program; helder.view.graph's
// readers (a signal, a memo, a Read, an asset) as functions, the same value
// again when they come back. A call of a signal the program writes is
// chosen by its static type (signalRead, signalWrite, signalUpdate), never
// by testing the value: the function itself, called dynamically, reads with
// no argument and writes with one, a function written being a divergence.
class Interop {
	// (never true: the manifest's keep names its functions under it; dynamic,
	// so that no optimizer of Haxe's or hxmc's folds it)
	public static dynamic function keeping():Bool return false;

	// a Haxe value as JavaScript's: numbers Float, arrays, functions and
	// structures made JavaScript's, the rest as it is
	public static function toJs(v:Dynamic):Dynamic {
		if (v == null) return null;
		if (Std.isOfType(v, JsObject) || Std.isOfType(v, String) || Std.isOfType(v, Bool)) return v;
		if (Std.isOfType(v, helder.view.graph.Read.Reader)) return callable(v);
		if (Std.isOfType(v, Int)) {
			var i:Int = v;
			return (i : Float);
		}
		if (Std.isOfType(v, Float)) return v;
		if (Std.isOfType(v, Array)) return Lib.array([for (x in (v : Array<Dynamic>)) toJs(x)]);
		// (helder's async work, a task, an asset's load: a promise of its answer)
		if (Std.isOfType(v, helder.async.Task)) return taskPromise(v);
		if (Std.isOfType(v, helder.view.graph.Awaitable)) return Promises.ofAwaitable(v);
		// (helder's bytes: a Uint8Array sharing them)
		if (Std.isOfType(v, haxe.io.Bytes)) return TypedArrays.ofBytes(v);
		if (Reflect.isFunction(v))
			return Builtins.nativeFunction("", 0, (_, args, _) -> toJs(Reflect.callMethod(null, v, [for (a in args) toHaxe(a)])));
		if (Type.typeof(v) == TObject) {
			var o = new JsObject(Builtins.ObjectProto);
			for (k in Reflect.fields(v)) o.setOwn(k, toJs(Reflect.field(v, k)));
			return o;
		}
		return v;
	}

	// a task of helder.async's as a promise: its result, its error as an
	// Error (a cancellation an AbortError); the promise cancelled, the task
	static function taskPromise(t:helder.async.Task<Dynamic>):Dynamic {
		var later = new helder.view.graph.Awaitable.Later<Dynamic>();
		t.onCompletion((r, e) -> if (e == null) later.resolve(r) else if (Std.isOfType(e, haxe.exceptions.CancellationException)) later.reject(Promises.abortError())
			else later.reject(Builtins.makeError("Error", e.message)));
		var p:Promises.JsPromise = Promises.ofAwaitable(later);
		p.canceller = () -> t.cancel();
		return p;
	}

	// a JavaScript value as Haxe code takes one untyped: arrays Haxe's,
	// functions closures (any arity), plain objects structures, undefined null
	public static function toHaxe(v:Dynamic):Dynamic {
		if (v == null || v == Seed.undefinedValue) return null;
		if (Std.isOfType(v, JsFunction) && (v : JsFunction).haxe != null) return (v : JsFunction).haxe;
		if (Std.isOfType(v, JsArray)) return [for (x in (v : JsArray).items) x == Lib.hole ? null : toHaxe(x)];
		// (a typed array, a DataView, an ArrayBuffer: its bytes, shared when it views all its buffer's)
		if (Std.isOfType(v, TypedArrays.JsTypedArray) || Std.isOfType(v, JsBuffer) || Std.isOfType(v, JsDataView)) return TypedArrays.bytesOf(v);
		if (Std.isOfType(v, JsFunction)) {
			var f = v;
			return Reflect.makeVarArgs(args -> toHaxe(call(f, [for (a in args) toJs(a)])));
		}
		if (Std.isOfType(v, JsObject) && (v : JsObject).proto == Builtins.ObjectProto && !Std.isOfType(v, JsFunction)) {
			var o:Dynamic = {};
			var names = (v : JsObject).ownNames();
			if (names != null) for (k in names) Reflect.setField(o, k, toHaxe(Lib.get(v, k)));
			return o;
		}
		return v;
	}

	// a typed array's, a DataView's or an ArrayBuffer's bytes, as Haxe's
	// Bytes takes them (shared when the view is all its buffer: TypedArrays.bytesOf)
	public static function bytes(v:Dynamic, where:String):haxe.io.Bytes {
		if (v == null || v == Seed.undefinedValue) return null;
		var b = TypedArrays.bytesOf(v);
		if (b == null) Seed.diverge("a typed array, a DataView or an ArrayBuffer", v, where);
		return b;
	}

	// Haxe's Bytes as a typed array of kind sharing them
	public static function bytesToJs(v:Dynamic, kind:String):Dynamic {
		if (v == null) return null;
		return TypedArrays.ofBytes(v, kind == "Uint8ClampedArray" ? TypedArrays.UINT8C : kind == "Int8Array" ? TypedArrays.INT8 : TypedArrays.UINT8);
	}

	// f called with args (JavaScript's values), this undefined
	public static function call(f:Dynamic, args:Array<Dynamic>):Dynamic return Lib.call(f, Seed.undefinedValue, args);

	// (the functions the program sees for nodes)
	static final callables = new haxe.ds.ObjectMap<Dynamic, JsFunction>();

	// a reader as JavaScript's function: read with no argument; a signal
	// written with one (a dynamic call: a static one is signalWrite or
	// signalUpdate, by the argument's type), a function a divergence
	static function callable(r:helder.view.graph.Read.Reader<Dynamic>):JsFunction {
		var f = callables.get(r);
		if (f != null) return f;
		f = Builtins.nativeFunction("", 0, (_, args, _) -> {
			if (args.length == 0) return toJs(r.read());
			if (!Std.isOfType(r, helder.view.graph.Node)) throw "helder.view: a memo or a Read is read only";
			var n:helder.view.graph.Node<Dynamic> = cast r, a:Dynamic = args[0];
			if (Std.isOfType(a, JsFunction) && (a : JsFunction).haxe == null) Seed.diverge("a value (a signal holds no function: update it where its type says so)", a, "a signal written");
			n.write(toHaxe(a));
			return Seed.undefinedValue;
		});
		f.setOwn("peek", Builtins.nativeFunction("peek", 0, (_, _, _) -> toJs(r.peek())));
		f.haxe = r;
		if (Std.isOfType(r, helder.view.graph.Node)) callables.set(r, f);
		return f;
	}

	// (a signal's or a memo's node, when f is one's function)
	static function nodeOf(f:Dynamic):Null<helder.view.graph.Read.Reader<Dynamic>>
		return Std.isOfType(f, JsFunction) && Std.isOfType((f : JsFunction).haxe, helder.view.graph.Read.Reader) ? (f : JsFunction).haxe : null;

	// f() where f's type is a Signal or a Memo: its node read (else f called)
	public static function signalRead(f:Dynamic):Dynamic {
		var r = nodeOf(f);
		return r != null ? toJs(r.read()) : call(f, []);
	}

	// f(v) where f's type is a Signal and v's no function: written, a function a divergence
	public static function signalWrite(f:Dynamic, v:Dynamic, where:String):Dynamic {
		var r = nodeOf(f);
		if (r == null) return call(f, [v]);
		if (!Std.isOfType(r, helder.view.graph.Node)) throw "helder.view: a memo or a Read is read only";
		if (Std.isOfType(v, JsFunction) && (v : JsFunction).haxe == null) Seed.diverge("a value (a signal holds no function)", v, where);
		(cast r : helder.view.graph.Node<Dynamic>).write(toHaxe(v));
		return Seed.undefinedValue;
	}

	// f(update) where f's type is a Signal and update's a function: updated from the latest value
	public static function signalUpdate(f:Dynamic, update:Dynamic):Dynamic {
		var r = nodeOf(f);
		if (r == null) return call(f, [update]);
		if (!Std.isOfType(r, helder.view.graph.Node)) throw "helder.view: a memo or a Read is read only";
		(cast r : helder.view.graph.Node<Dynamic>).update(x -> toHaxe(call(update, [toJs(x)])));
		return Seed.undefinedValue;
	}

	// a Read from the program's value: a reader of helder's as it is, a function read by calling it, else a constant
	public static function reader(v:Dynamic):Dynamic {
		if (v == Seed.undefinedValue || v == null) return new helder.view.graph.Read.Const<Dynamic>(null);
		if (Std.isOfType(v, JsFunction)) {
			var f:JsFunction = v;
			if (f.haxe != null) return f.haxe;
			return new helder.view.graph.Read.Thunk<Dynamic>(() -> toHaxe(call(f, [])));
		}
		return new helder.view.graph.Read.Const<Dynamic>(toHaxe(v));
	}

	// a program's component's Read prop: a function as it is (a signal's, a
	// bound hole's), another value one giving it (a constant's cell, as Haxe's @:from makes it)
	public static function readFunction(v:Dynamic):Dynamic {
		if (Std.isOfType(v, JsFunction)) return v;
		var value = v;
		return Builtins.nativeFunction("", 0, (_, _, _) -> value);
	}

	public static function isNullish(v:Dynamic):Bool return v == null || v == Seed.undefinedValue;

	public static function int(v:Dynamic, where:String):Int {
		if (!Std.isOfType(v, Float)) Seed.diverge("a number", v, where);
		var f:Float = v;
		return Std.int(f);
	}

	public static function float(v:Dynamic, where:String):Float {
		if (!Std.isOfType(v, Float)) Seed.diverge("a number", v, where);
		return v;
	}

	public static function bool(v:Dynamic, where:String):Bool {
		if (!Std.isOfType(v, Bool)) Seed.diverge("a boolean", v, where);
		return v;
	}

	public static function string(v:Dynamic, where:String):String {
		if (v == null || v == Seed.undefinedValue) return null;
		if (!Std.isOfType(v, String)) Seed.diverge("a string", v, where);
		return v;
	}

	// a value the program got from Haxe, as Haxe has it (a node's function its node; undefined null)
	public static function unwrap(v:Dynamic):Dynamic {
		if (v == Seed.undefinedValue) return null;
		if (Std.isOfType(v, JsFunction) && (v : JsFunction).haxe != null) return (v : JsFunction).haxe;
		return v;
	}

	// a JavaScript array's elements (undefined where it has holes)
	public static function items(v:Dynamic, where:String):Array<Dynamic> {
		if (!Std.isOfType(v, JsArray)) Seed.diverge("an array", v, where);
		return [for (x in (v : JsArray).items) x == Lib.hole ? Seed.undefinedValue : x];
	}

	// a property of an object (undefined on null and undefined)
	public static function field(o:Dynamic, name:String):Dynamic return isNullish(o) ? Seed.undefinedValue : Lib.get(o, name);

	// (markup: a function of Haxe's called with one value, a ref; fast refresh's scope of a keyed component)
	public static function apply1(f:Dynamic, v:Dynamic):Void
		if (f != null) Reflect.callMethod(null, f, [v]);

	public static function keyScope(name:String, key:Dynamic):String return name + "[" + Std.string(key) + "]";

	// (what a renderer cannot do: an agnostic literal's code for it, a component it has no version of)
	public static function fail(message:String):Dynamic throw message;

	// (helder dev) the signal f, its value the last build's signal's of this
	// key (Hot's, in its scope) when its initial value's source is the same;
	// saved on each snapshot when it is data (helder.view.Refresh's, for a
	// program's values: undefined, numbers, strings, booleans, null, arrays
	// and plain objects of them)
	public static function hotSignal(f:Dynamic, key:String, type:String, init:String):Dynamic {
		#if hxmc.dev
		var s:helder.view.graph.Signal<Dynamic> = cast unwrap(f);
		var last:Null<{v:Dynamic, i:String}> = helder.dev.Hot.load(key, type);
		if (last != null && last.i != init) {
			Sys.stderr().writeString("helder.dev: " + helder.dev.Hot.path() + (helder.dev.Hot.path() == "" ? "" : "/") + key + " reset: its initial value changed\n");
			last = null;
		}
		if (last != null) @:privateAccess s.node().value = toHaxe(fromTree(last.v));
		helder.view.graph.Graph.onCleanup(helder.dev.Hot.onSnapshot(() -> {
			var tree:Dynamic = try toTree(toJs(s.peek())) catch (e:Dynamic) {
				Sys.stderr().writeString("helder.dev: " + key + " not kept: " + Std.string(e) + "\n");
				return;
			}
			helder.dev.Hot.save(key, {v: tree, i: init}, type);
		}));
		#end
		return f;
	}

	#if hxmc.dev
	// (a program's value as Haxe's serializer takes it, and back)
	static function toTree(v:Dynamic):Dynamic {
		if (v == Seed.undefinedValue) return {u: true};
		if (v == null || Std.isOfType(v, Float) || Std.isOfType(v, String) || Std.isOfType(v, Bool)) return v;
		if (Std.isOfType(v, JsArray)) return {a: [for (x in (v : JsArray).items) x == Lib.hole ? {u: true} : toTree(x)]};
		if (Std.isOfType(v, JsObject) && (v : JsObject).proto == Builtins.ObjectProto && !Std.isOfType(v, JsFunction)) {
			var o:JsObject = v, kv:Array<Dynamic> = [];
			for (k in Lib.keys(o)) {
				kv.push(k);
				kv.push(toTree(Lib.get(o, k)));
			}
			return {o: kv};
		}
		throw "not data (" + Seed.typeOf(v) + ")";
	}

	static function fromTree(t:Dynamic):Dynamic {
		if (t == null || Std.isOfType(t, Float) || Std.isOfType(t, String) || Std.isOfType(t, Bool)) return t;
		if (Reflect.hasField(t, "u")) return Seed.undefinedValue;
		if (Reflect.hasField(t, "a")) return Lib.array([for (x in (t.a : Array<Dynamic>)) fromTree(x)]);
		var kv:Array<Dynamic> = t.o;
		var o = new JsObject(Builtins.ObjectProto);
		var i = 0;
		while (i < kv.length) {
			o.setOwn(kv[i], fromTree(kv[i + 1]));
			i += 2;
		}
		return o;
	}
	#end

	// (a program of helder's API with promises or timers: its event loop
	// on helder.async's, which helder.os's App turns between its frames, and
	// which commits helder.view's writes at the end of each of its turns)
	public static function hostLoop():Void
		if (Promises.eventHost == null) Promises.eventHost = new LoopHost();
}

// The JavaScript event loop's work on helder.async's loop (Promises.EventHost).
private class LoopHost implements Promises.EventHost {
	final loop = helder.async.Loop.current();
	final turn:Checkpoint;

	public function new()
		turn = new Checkpoint();

	public function checkpoint()
		if (!turn.queued) {
			turn.queued = true;
			loop.dispatch(turn);
		}

	public function timer(ms:Float, f:Void->Void):Void->Void {
		var t = loop.at(haxe.Timer.stamp() + ms / 1000, new TimerCall(loop.context(), f));
		return () -> t.close();
	}

	// (under helder dev, the dev server heard each turn: its reload ends it;
	// in the browser it returns, the page turning the loop)
	public function run() {
		#if (hxmc.target == "wasm32-wasi")
		loop.run();
		#else
		while (Promises.devTurn() && loop.turn(#if hxmc.dev 0.05 #else -1 #end)) {}
		#end
	}
}

private class Checkpoint implements haxe.coro.dispatchers.IDispatchObject {
	public var queued = false;

	public function new() {}

	public function onDispatch() {
		queued = false;
		Promises.drain();
	}
}

private class TimerCall implements haxe.coro.IContinuation<Any> {
	public var context(get, never):haxe.coro.context.Context;

	final ctx:haxe.coro.context.Context;
	final f:Void->Void;

	public function new(ctx, f) {
		this.ctx = ctx;
		this.f = f;
	}

	inline function get_context()
		return ctx;

	public function resume(_:Any, _:haxe.Exception)
		f();
}
