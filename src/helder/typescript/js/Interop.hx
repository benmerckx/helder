package helder.typescript.js;

import helder.typescript.js.Values;

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
		if (Reflect.isFunction(v))
			return Builtins.nativeFunction("", 0, (_, args, _) -> toJs(Reflect.callMethod(null, v, [for (a in args) toHaxe(a)])));
		if (Type.typeof(v) == TObject) {
			var o = new JsObject(Builtins.ObjectProto);
			for (k in Reflect.fields(v)) o.setOwn(k, toJs(Reflect.field(v, k)));
			return o;
		}
		return v;
	}

	// a JavaScript value as Haxe code takes one untyped: arrays Haxe's,
	// functions closures (any arity), plain objects structures, undefined null
	public static function toHaxe(v:Dynamic):Dynamic {
		if (v == null || v == Seed.undefinedValue) return null;
		if (Std.isOfType(v, JsFunction) && (v : JsFunction).haxe != null) return (v : JsFunction).haxe;
		if (Std.isOfType(v, JsArray)) return [for (x in (v : JsArray).items) x == Lib.hole ? null : toHaxe(x)];
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
}
