package helder.view;

#if macro
import haxe.macro.Context;
#end
import haxe.macro.Expr;
import helder.view.Memo;
import helder.view.Signal;

// Mounting content: render and insert go to the runtime (ViewRuntime) of the
// renderer whose nodes parent is, chosen by its type when compiling (its
// class's @:rendered, HostMacro.rendererOf); what is mounted there is made
// by that renderer, components and all, and a literal given here is
// compiled for it. A component that makes a node of one renderer and
// renders into it with another is a boundary (<Scene>: a ui node, scene
// nodes in it); content passes through it unchanged. open mounts content
// with no parent: a program's root, components making roots of their own
// (<Surface>s).
class Render {
	// (the renderer mounting a component, its id (idOf): ViewRuntime.component; Pick.call)
	@:noCompletion public static var pass = 0;

	// renders content into parent (its root: dispose removes it and stops its effects)
	public static macro function render(content:Expr, parent:Expr):Expr {
		var r = rendererFor(parent);
		var rt = HostMacro.runtime(r);
		return macro $p{rt}.render(${MarkupMacro.place(content, r)}, $parent);
	}

	// inserts content into parent before a node (null: at the end); the nodes made
	public static macro function insert(content:Expr, parent:Expr, before:Expr):Expr {
		var r = rendererFor(parent);
		var rt = HostMacro.runtime(r);
		return macro $p{rt}.insert(${MarkupMacro.place(content, r)}, $parent, $before);
	}

	// render and insert with a renderer named (its class): for node types its
	// package cannot mark (@:rendered), as the DOM's (DomRenderer.render)
	public static macro function renderAs(renderer:Expr, content:Expr, parent:Expr):Expr {
		var r = HostMacro.resolve(renderer);
		return macro $p{HostMacro.runtime(r)}.render(${MarkupMacro.place(content, r)}, $parent);
	}

	public static macro function insertAs(renderer:Expr, content:Expr, parent:Expr, before:Expr):Expr {
		var r = HostMacro.resolve(renderer);
		return macro $p{HostMacro.runtime(r)}.insert(${MarkupMacro.place(content, r)}, $parent, $before);
	}

	// a renderer's identity at run time (View.renderer, pass), by its class: a constant
	public static macro function idOf(renderer:Expr):Expr
		return macro $v{HostMacro.id(HostMacro.resolve(renderer))};

	#if macro
	static function rendererFor(parent:Expr):String {
		var t = Context.typeof(parent);
		var r = HostMacro.rendererOf(t);
		if (r == null)
			Context.error("helder.view: " + haxe.macro.TypeTools.toString(t) + " is no renderer's node (its class names its renderer with @:rendered(...); the renderers reached: "
				+ @:privateAccess HostMacro.reached.join(", ") + ")", parent.pos);
		return r;
	}
	#end

	#if !macro
	// mounts content that has no parent, a program's root (RootView: a
	// literal of components only): components that make roots of their own
	// (<Surface>s, UiWindow.run), called in a root, what they return opened in
	// turn (a component's View); its dispose
	public static function open(content:RootView):Void->Void
		return Reactive.root(dispose -> {
			#if hxmc.dev
			// (hxmc dev: its roots' cleanups, their windows' closing, run before the next build starts)
			Reactive.onCleanup(helder.dev.Hot.onDispose(dispose));
			#end
			Reactive.untrack(() -> values(content));
			dispose;
		});

	static function values(v:Dynamic) {
		if (v == null) return;
		if (Std.isOfType(v, View)) {
			var parts = (v : View).parts;
			if (parts == null) throw "helder.view: " + Std.string(v) + " has elements or text, which need a parent (Render.render)";
			for (x in parts())
				values(x);
		} else if (Std.isOfType(v, Array)) {
			for (x in (v : Array<Dynamic>))
				values(x);
		} else if (isReactive(v)) {
			// (a region, Show's: what it gives opened again when it changes, the roots it opened before disposed)
			Reactive.effect(() -> {
				var x = read(v);
				Reactive.untrack(() -> values(x));
			});
		} else throw "helder.view: content with no parent is components only, not " + Std.string(v);
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
