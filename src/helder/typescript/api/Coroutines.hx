package helder.typescript.api;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

// helder's coroutines as TypeScript sees them: a @:coroutine function
// (haxe.coro.Coroutine<(args) -> R>) is an async function returning a
// Promise of R. The manifest (Manifest) lists it by a wrapper of its own,
// a plain function that starts the coroutine as a task (Async.launch: the
// program's promise, helder.async.Task's), and the declarations print the
// same signature (DefinitionEmitter), so a coroutine of helder's API is the
// program's with nothing written for it.
class Coroutines {
	// a coroutine field's arguments and result (null: not a coroutine)
	public static function of(f:ClassField):Null<{args:Array<{name:String, opt:Bool, t:Type}>, ret:Type}> {
		return switch Context.follow(f.type) {
			case TAbstract(_.get() => a, [inner]) if (a.pack.join(".") == "haxe.coro" && a.name == "Coroutine"):
				switch Context.follow(inner) {
					case TFun(args, ret): {args: args, ret: ret};
					case _: null;
				}
			case _: null;
		}
	}

	// the function TypeScript calls: the same arguments, a task of the result (a Promise)
	public static function promised(f:ClassField):Null<Type> {
		var co = of(f);
		return co == null ? null : TFun(co.args, task(co.ret));
	}

	// the wrapper's name, beside the class's other keeps
	public static inline function wrapperName(field:String):String
		return "__co_" + field;

	// a static starting the coroutine as a task: the class's static called by
	// its path, or a member on its first argument (self)
	public static function wrapper(f:ClassField, path:Array<String>, self:Null<ComplexType>, pos:Position):Field {
		var co = of(f);
		var name = f.name;
		var args:Array<FunctionArg> = [], call:Array<Expr> = [];
		if (self != null) args.push({name: "self", type: self});
		for (i in 0...co.args.length) {
			var a = co.args[i], n = "a" + i;
			args.push({name: n, opt: a.opt, type: Context.toComplexType(a.t)});
			call.push(macro $i{n});
		}
		var target = self != null ? macro @:privateAccess self.$name : macro @:privateAccess $p{path}.$name;
		var body = void(co.ret) ? macro {
			$target($a{call});
			return null;
		} : macro return $target($a{call});
		return {
			name: wrapperName(name),
			access: [APublic, AStatic],
			kind: FFun({args: args, ret: Context.toComplexType(task(co.ret)), expr: macro return helder.async.Async.launch(@:coroutine function(_) $body)}),
			pos: pos
		};
	}

	static function void(t:Type):Bool
		return switch Context.follow(t) {
			case TAbstract(_.get() => a, _): a.name == "Void" && a.pack.length == 0;
			case _: false;
		}

	static function task(ret:Type):Type
		return switch Context.getType("helder.async.Task") {
			case TInst(r, _): TInst(r, [void(ret) ? Context.getType("Any") : ret]);
			case t: t;
		}
}
#end
