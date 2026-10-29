package helder.view;

#if macro
import haxe.macro.Context;
#end
import haxe.macro.Expr;

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
	@:typescript @:typescript.mount @:typescript.type("(content: unknown, parent: unknown) => () => void")
	public static macro function render(content:Expr, parent:Expr):Expr {
		var r = rendererFor(parent);
		var rt = HostMacro.runtime(r);
		return macro $p{rt}.render(${MarkupMacro.place(content, r)}, $parent);
	}

	// inserts content into parent before a node (null: at the end); the nodes made
	@:typescript @:typescript.mount @:typescript.type("(content: unknown, parent: unknown, before: unknown) => unknown[]")
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
	public static function open(content:RootView):Void->Void {
		var top = helder.view.graph.Graph.getOwner() == null;
		var d = helder.view.graph.Graph.root(dispose -> {
			#if hxmc.dev
			// (hxmc dev: its roots' cleanups, their windows' closing, run before the next build starts)
			helder.view.graph.Graph.onCleanup(helder.dev.Hot.onDispose(dispose));
			#end
			helder.view.graph.Graph.untrack(() -> values(content));
			dispose;
		});
		if (top) helder.view.graph.Graph.flush();
		return d;
	}

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
			var home = helder.view.graph.Graph.getOwner(), shown:Null<helder.view.graph.Owner> = null;
			helder.view.graph.Graph.renderEffect(() -> read(v), (x:Dynamic) -> {
				if (shown != null) shown.dispose();
				shown = new helder.view.graph.Owner(home);
				helder.view.graph.Graph.runWithOwner(shown, () -> values(x));
			});
			helder.view.graph.Graph.onCleanup(() -> if (shown != null) shown.dispose());
		} else if (Std.isOfType(v, helder.view.graph.Read.Const)) values((v : helder.view.graph.Read.Const<Dynamic>).value);
		else throw "helder.view: content with no parent is components only, not " + Std.string(v);
	}

	// whether a value is reactive: a node (a signal, a memo), a Read of one or
	// of a function, a function (a hole that may read: () -> ...); a Read's
	// constant is not
	public static function isReactive(v:Dynamic):Bool
		return v != null && ((Std.isOfType(v, helder.view.graph.Read.Reader) && !Std.isOfType(v, helder.view.graph.Read.Const)) || Reflect.isFunction(v));

	// a reactive value's value (tracked), else the value; a node or a Read
	// that it gives read in turn ({row()} of a list of signals: its value)
	public static function read(v:Dynamic):Dynamic {
		if (Std.isOfType(v, helder.view.graph.Read.Reader)) v = (v : helder.view.graph.Read.Reader<Dynamic>).read();
		else if (Reflect.isFunction(v)) v = (v : Void->Dynamic)();
		else return v;
		while (Std.isOfType(v, helder.view.graph.Read.Reader))
			v = (v : helder.view.graph.Read.Reader<Dynamic>).read();
		return v;
	}
	#end
}
