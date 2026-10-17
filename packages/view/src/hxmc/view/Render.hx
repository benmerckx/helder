package hxmc.view;

#if macro
import haxe.macro.Context;
#end
import haxe.macro.Expr;
import hxmc.view.Memo;
import hxmc.view.Signal;

// Mounting content: render and insert go to the runtime (Runtime) of the
// renderer whose nodes parent is, chosen by its type when compiling; what
// is mounted there is made by that renderer, components and all. A
// component that makes a node of one renderer and renders into it with
// another is a boundary (a ui canvas in a page, a page's element over a
// canvas); content passes through it unchanged.
class Render {
	// renders content into parent (its root: dispose removes it and stops its effects)
	public static macro function render(content:Expr, parent:Expr):Expr {
		var r = runtimeFor(parent);
		return macro $p{r}.render($content, $parent);
	}

	// inserts content into parent before a node (null: at the end); the nodes made
	public static macro function insert(content:Expr, parent:Expr, before:Expr):Expr {
		var r = runtimeFor(parent);
		return macro $p{r}.insert($content, $parent, $before);
	}

	#if macro
	static function runtimeFor(parent:Expr):Array<String> {
		var t = Context.typeof(parent);
		var i = HostMacro.rendererOf(t);
		if (i < 0)
			Context.error("hxmc.view: " + haxe.macro.TypeTools.toString(t) + " is no renderer's node (renderers: "
				+ [for (r in HostMacro.renderers()) r.path].join(", ") + ")", parent.pos);
		return HostMacro.runtime(i);
	}
	#end

	public static function isReactive(v:Dynamic):Bool
		return v != null && (Std.isOfType(v, SignalBase) || Std.isOfType(v, MemoBase) || Reflect.isFunction(v));

	// a reactive value's value (tracked)
	public static function read(v:Dynamic):Dynamic {
		if (Std.isOfType(v, SignalBase)) return (cast v : Signal<Dynamic>).value;
		if (Std.isOfType(v, MemoBase)) return (cast v : Memo<Dynamic>).value;
		if (Reflect.isFunction(v)) return (v : Void->Dynamic)();
		return v;
	}
}
