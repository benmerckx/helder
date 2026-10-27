package helder.scoped;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.Tools;
using Lambda;
#end

// What the Scoped macro's loops use (Scoped.hx).
class Loops {
	// a SliceView of e when e is a Slice; e itself otherwise (a Grow keeps its
	// checks: it may be truncated in the loop)
	public static macro function view(e:Expr):Expr {
		return switch Context.follow(Context.typeof(e)) {
			case TAbstract(_.get() => {pack: ["helder", "scoped"], name: "Slice"}, _):
				macro new helder.scoped.Slice.SliceView($e);
			default:
				e;
		}
	}

	// a SliceChecked of e when e is a Slice (its header read once, every
	// index still checked); e itself otherwise
	public static macro function checked(e:Expr):Expr {
		return switch Context.follow(Context.typeof(e)) {
			case TAbstract(_.get() => {pack: ["helder", "scoped"], name: "Slice"}, _):
				macro new helder.scoped.Slice.SliceChecked($e);
			default:
				e;
		}
	}

	// a loop's body as an iteration scope: what the previous iteration
	// allocated freed when the next starts (Memory.restore), unless nothing
	// in the body can allocate. The body is typed here, its inline calls
	// expanded, and searched for a call that may: an allocation of the
	// package's, a function that is not @:scoped with a scope of its own
	// (outside the standard library), a closure or a dynamic call. Either
	// way the body starts with `var __iteration`, which marks the iteration
	// for the checker (Check.hx).
	public static macro function iteration(top:Expr, claims:Expr, body:Expr):Expr {
		// (typed as a statement: the block's last expression is not its value)
		var typed = Context.typeExpr(macro {
			$body;
			0;
		});
		var check = mayAllocate(typed) ? macro helder.scoped.Memory.restore($top, $claims) : macro true;
		var stored = Context.storeTypedExpr(typed);
		return macro {
			var __iteration = $check;
			$stored;
		};
	}

	#if macro
	// (Memory's functions that do not move the stack's top or claim a buffer)
	static var keeps = [
		"reserve", "leaveSlow", "fail", "outOfRange", "outside", "used", "grows", "capacity", "zero", "copy", "string", "write", "restore", "top",
		"claims"
	];

	@:noCompletion public static function mayAllocate(e:TypedExpr):Bool {
		var found = false;
		function walk(e:TypedExpr) {
			if (found)
				return;
			switch e.expr {
				case TCall({expr: TField(_, FStatic(_.get() => c, _.get() => f))}, _) | TCall({expr: TField(_, FInstance(_.get() => c, _, _.get() => f))}, _):
					if (callAllocates(c, f))
						found = true;
				case TCall({expr: TField(_, FEnum(_, _))}, _):
				case TCall(_, _):
					// (a closure, a local function, a dynamic call)
					found = true;
				case TNew(_.get() => c, _, _):
					var ctor = c.constructor == null ? null : c.constructor.get();
					if (!isStd(c) && !(ctor != null && ctor.kind.match(FMethod(MethInline)) && c.meta.has(":valueLayout")))
						found = true;
				case TFunction(_):
					// (a closure's body runs when it is called, which is checked)
					return;
				default:
			}
			e.iter(walk);
		}
		walk(e);
		return found;
	}

	static function callAllocates(c:ClassType, f:ClassField):Bool {
		if (f.meta.has(":noAlloc"))
			return false;
		if (c.pack.length >= 2 && c.pack[0] == "helder" && c.pack[1] == "scoped")
			return switch c.name {
				case "Store" | "Header": false;
				case "Memory": !keeps.contains(f.name);
				default: true;
			}
		if (f.meta.has(":scopedFrees"))
			return false;
		return !isStd(c);
	}

	// a class of the standard library: it cannot allocate scoped memory
	static function isStd(c:ClassType):Bool {
		var file = Context.getPosInfos(c.pos).file;
		for (cp in Context.getClassPath())
			if (cp.length > 0 && StringTools.endsWith(haxe.io.Path.removeTrailingSlashes(cp), "std") && StringTools.startsWith(file, cp))
				return true;
		return c.isExtern;
	}
	#end
}
