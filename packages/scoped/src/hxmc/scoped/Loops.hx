package hxmc.scoped;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

// What the Scoped macro's loops use (Scoped.hx, "Loops over a slice").
class Loops {
	// a SliceView of e when e is a Slice; e itself otherwise (a Grow keeps its
	// checks: it may be truncated in the loop)
	public static macro function view(e:Expr):Expr {
		return switch Context.follow(Context.typeof(e)) {
			case TAbstract(_.get() => {pack: ["hxmc", "scoped"], name: "Slice"}, _):
				macro new hxmc.scoped.Slice.SliceView($e);
			default:
				e;
		}
	}
}
