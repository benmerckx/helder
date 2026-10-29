package helder.typescript.js;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;
#else
import helder.typescript.js.Values;
#end

// Values between a TypeScript program and helder's Haxe API, as the glue
// the compiler writes for the program's calls, members and TSX passes them
// (helder.typescript.glue): a JavaScript value into the type Haxe expects
// where it goes (fromJs, a macro reading that type), or into what Haxe
// code takes untyped (toHaxe: arrays, functions and plain objects made
// Haxe's); a Haxe value back to JavaScript (toJs). Haxe objects (a View, a
// node) pass as they are, opaque to the program; helder.view.graph's
// readers (a signal, a memo, a Read, an asset) as functions, called to read
// a signal and to write it (one function, cached per node), the same value
// again when they come back.
class Interop {
	#if !macro
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

	public static function call(f:Dynamic, args:Array<Dynamic>):Dynamic return Lib.call(f, Seed.undefinedValue, args);

	// (the functions the program sees for nodes)
	static final callables = new haxe.ds.ObjectMap<Dynamic, JsFunction>();

	// a reader as JavaScript's function: read with no argument; a signal
	// written with one, updated with a function (a signal never holds one)
	static function callable(r:helder.view.graph.Read.Reader<Dynamic>):JsFunction {
		var f = callables.get(r);
		if (f != null) return f;
		f = Builtins.nativeFunction("", 0, (_, args, _) -> {
			if (args.length == 0) return toJs(r.read());
			if (!Std.isOfType(r, helder.view.graph.Node)) throw "helder.view: a memo or a Read is read only";
			var n:helder.view.graph.Node<Dynamic> = cast r, a:Dynamic = args[0];
			if (Std.isOfType(a, JsFunction) && (a : JsFunction).haxe == null) n.update(x -> toHaxe(call(a, [toJs(x)]))) else n.write(toHaxe(a));
			return Seed.undefinedValue;
		});
		f.setOwn("peek", Builtins.nativeFunction("peek", 0, (_, _, _) -> toJs(r.peek())));
		f.haxe = r;
		if (Std.isOfType(r, helder.view.graph.Node)) callables.set(r, f);
		return f;
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

	public static function isNullish(v:Dynamic):Bool return v == null || v == Seed.undefinedValue;

	public static function isString(v:Dynamic):Bool return Std.isOfType(v, String);

	public static function isNumber(v:Dynamic):Bool return Std.isOfType(v, Float);

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
		if (!Std.isOfType(v, String)) Seed.diverge("a string", v, where);
		return v;
	}

	// an instance of a Haxe class (a value the program got from Haxe)
	public static function instance(v:Dynamic, c:Class<Dynamic>, where:String):Dynamic {
		if (v == Seed.undefinedValue) return null;
		if (Std.isOfType(v, JsFunction) && (v : JsFunction).haxe != null) v = (v : JsFunction).haxe;
		if (v != null && !Std.isOfType(v, c)) Seed.diverge("a " + Type.getClassName(c), v, where);
		return v;
	}

	// a JavaScript array's elements
	public static function items(v:Dynamic, where:String):Array<Dynamic> {
		if (!Std.isOfType(v, JsArray)) Seed.diverge("an array", v, where);
		return [for (x in (v : JsArray).items) x == Lib.hole ? Seed.undefinedValue : x];
	}

	public static function field(o:Dynamic, name:String):Dynamic return isNullish(o) ? Seed.undefinedValue : Lib.get(o, name);

	// a TypeScript component's view: its function called with the props (children a View)
	public static function component(f:Dynamic, props:Dynamic):Dynamic return toHaxe(call(f, [toJs(props)]));
	#end

	// a call's or a member's value, as JavaScript's (undefined for Void),
	// typed once (markup in it compiled once), at its place in the program
	public static macro function result(e:Expr, file:String, min:Int, max:Int):Expr {
		var typed = Context.typeExpr(placed(e, Context.makePosition({file: file, min: min, max: max})));
		var stored = Context.storeTypedExpr(typed);
		return switch Context.follow(typed.t) {
			case TAbstract(_.get() => {name: "Void", pack: []}, _): macro {
					$stored;
					helder.typescript.js.Seed.getUndefined();
				};
			case _: macro helder.typescript.js.Interop.toJs($stored);
		}
	}

	// e at its place in the program (min to max, bytes, in file): Haxe's errors there
	public static macro function at(e:Expr, file:String, min:Int, max:Int):Expr
		return placed(e, Context.makePosition({file: file, min: min, max: max}));

	// v (a JavaScript value) as the type expected where it goes, checked
	// (TSHX100 where it is not one, at where); without one, toHaxe's
	public static macro function fromJs(v:Expr, where:Expr):Expr {
		var t = Context.getExpectedType();
		return t == null ? macro helder.typescript.js.Interop.toHaxe($v) : convert(v, t, where, 0);
	}

	#if macro
	// (markup keeps its own positions: the markup macro reads its source by them)
	static function placed(e:Expr, pos:Position):Expr return switch e.expr {
		case ECall({expr: EField(_, "literal" | "literalFor")}, _): e;
		case _: {expr: haxe.macro.ExprTools.map(e, x -> placed(x, pos)).expr, pos: pos};
	}

	static function convert(v:Expr, t:Type, where:Expr, depth:Int):Expr {
		var ct = TypeTools.toComplexType(t);
		if (depth > 8 || ct == null) return macro helder.typescript.js.Interop.toHaxe($v);
		return switch Context.follow(t, true) {
			case TMono(_) | TDynamic(_): macro helder.typescript.js.Interop.toHaxe($v);
			// (a Read: what reads, helder.view.graph)
			case TAbstract(_.get() => {pack: ["helder", "view", "graph"], name: "Read"}, _): macro(cast helder.typescript.js.Interop.reader($v) : $ct);
			case TAbstract(_.get() => a, params):
				switch a.pack.length == 0 ? a.name : "" {
					case "Int": macro helder.typescript.js.Interop.int($v, $where);
					case "Float": macro helder.typescript.js.Interop.float($v, $where);
					case "Bool": macro helder.typescript.js.Interop.bool($v, $where);
					case "Any": macro helder.typescript.js.Interop.toHaxe($v);
					case "Null":
						var inner = convert(macro value, params[0], where, depth + 1);
						macro {
							var value:Dynamic = $v;
							helder.typescript.js.Interop.isNullish(value) ? null : $inner;
						};
					case _: abstractValue(v, t, ct, where, depth);
				}
			case TInst(_.get() => c, params):
				switch c.kind {
					case KTypeParameter(_): macro helder.typescript.js.Interop.toHaxe($v);
					case _ if (c.pack.length == 0 && c.name == "String"): macro helder.typescript.js.Interop.string($v, $where);
					case _ if (c.pack.length == 0 && c.name == "Array"):
						var elem = TypeTools.toComplexType(params[0]);
						var each = convert(macro x, params[0], where, depth + 1);
						macro {
							var out:Array<$elem> = [];
							for (x in helder.typescript.js.Interop.items($v, $where)) out.push($each);
							out;
						};
					case _ if (c.isInterface || c.isExtern): macro(cast helder.typescript.js.Interop.toHaxe($v) : $ct);
					case _:
						// (a class of a module of another name: Module.Name)
						var module = c.module.split(".");
						var path = module[module.length - 1] == c.name ? c.pack.concat([c.name]) : module.concat([c.name]);
						macro(cast helder.typescript.js.Interop.instance($v, $p{path}, $where) : $ct);
				}
			case TFun(args, ret):
				var params:Array<FunctionArg> = [for (i in 0...args.length) {name: "a" + i, type: TypeTools.toComplexType(args[i].t)}];
				var passed = [for (i in 0...args.length) macro helder.typescript.js.Interop.toJs($i{"a" + i})];
				var call = macro helder.typescript.js.Interop.call(f, $a{passed});
				var body = switch Context.follow(ret) {
					case TAbstract(_.get() => {name: "Void", pack: []}, _): macro $call;
					case _: macro return ${convert(call, ret, where, depth + 1)};
				};
				var fn:Expr = {expr: EFunction(FAnonymous, {args: params, ret: TypeTools.toComplexType(ret), expr: body}), pos: Context.currentPos()};
				macro {
					var f:Dynamic = $v;
					helder.typescript.js.Interop.isNullish(f) ? null : $fn;
				};
			case TAnonymous(_.get() => an):
				var fields:Array<ObjectField> = [];
				for (f in an.fields) {
					var get = macro helder.typescript.js.Interop.field(o, $v{f.name});
					var value = convert(get, f.type, where, depth + 1);
					fields.push({field: f.name, expr: f.meta.has(":optional") ? macro helder.typescript.js.Interop.isNullish($get) ? null : $value : value});
				}
				var obj:Expr = {expr: EObjectDecl(fields), pos: Context.currentPos()};
				macro {
					var o:Dynamic = $v;
					($obj : $ct);
				};
			case TEnum(_, _): macro(cast $v:$ct);
			case _: macro(cast helder.typescript.js.Interop.toHaxe($v) : $ct);
		}
	}

	// an abstract: from a string or a number where it takes one (its @:from
	// casts), else as its underlying type
	static function abstractValue(v:Expr, t:Type, ct:ComplexType, where:Expr, depth:Int):Expr {
		var takesString = Context.unify(Context.getType("String"), t), takesFloat = Context.unify(Context.getType("Float"), t),
			takesInt = Context.unify(Context.getType("Int"), t);
		var under = TypeTools.followWithAbstracts(t, true);
		var fallback = Context.unify(under, t) ? macro(${convert(macro value, under, where, depth + 1)} : $ct) : macro(cast ${convert(macro value, under, where, depth + 1)} : $ct);
		var e = fallback;
		if (takesInt && !takesFloat) e = macro helder.typescript.js.Interop.isNumber(value) ? (helder.typescript.js.Interop.int(value, $where) : $ct) : $e;
		if (takesFloat) e = macro helder.typescript.js.Interop.isNumber(value) ? (helder.typescript.js.Interop.float(value, $where) : $ct) : $e;
		if (takesString) e = macro helder.typescript.js.Interop.isString(value) ? (helder.typescript.js.Interop.string(value, $where) : $ct) : $e;
		return macro {
			var value:Dynamic = $v;
			$e;
		};
	}
	#end
}
