package helder.view;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

// Fast refresh for helder.view under `helder dev` (-D hxmc.dev),
// written on helder.dev.Hot's public calls only, as any state library would
// be. A signal's key is the static place it is made (HotMacro.here: the
// type, the function, the variable it is assigned to) inside the scope of
// the component instance making it: the markup macro runs each component
// in Hot.scope(its name, or name[key] with a `key` attribute; a second one
// in the same place name#1), each row of For and Index in a scope of its
// position, and each computation in a scope of its own (Computation), so
// that what an effect makes again later is keyed as when it first ran.
// The value is saved on each snapshot with its type's hash, and read back
// when the signal is made again in the next build, if the type is the
// same; a signal whose type is not data (or not known where it is made:
// `signal([])` with nothing to say what the array holds) is not kept.
// The initial value's source is hashed with it (as React does for
// useState): `signal(0)` edited to `signal(5)` starts at 5, said so in the
// terminal, rather than keeping the old build's value. A class (or the
// function the signal is made in) marked @:hot(reset) keeps none of its
// signals: each build starts them afresh (React's `@refresh reset`).
// Without -D hxmc.dev none of this is compiled (Graph.signal is
// Graph.signalOf). A derived signal (signal(fn)) is not kept.
class Refresh {
	#if macro
	// Graph.signal(init, ?options) under -D hxmc.dev: a value's signal kept by
	// its key; a derived one (a function) as it is
	public static function signal(init:Expr, rest:Array<Expr>):Expr {
		var made = {expr: ECall(macro @:pos(init.pos) helder.view.graph.Graph.signalOf, [init].concat(rest)), pos: init.pos};
		var t = try Context.typeof(init) catch (_:Dynamic) null;
		if (t == null) return made;
		switch Context.follow(t) {
			case TFun(_, _): return made;
			case _:
		}
		var key = helder.dev.HotMacro.here(Context.currentPos());
		var type = helder.dev.HotMacro.hash(t);
		// (a value whose type is not known yet: the type expected, `var s:Signal<Array<String>> = signal([])`)
		if (type == "") {
			var expected = Context.getExpectedType();
			if (expected != null)
				switch Context.follow(expected) {
					case TAbstract(_.get() => {pack: ["helder", "view", "graph"], name: "Signal"}, [p]): type = helder.dev.HotMacro.hash(p);
					case _:
				}
		}
		// (the initial value's source, whitespace aside; @:hot(reset) where it is made)
		var source = haxe.crypto.Md5.encode(haxe.macro.ExprTools.toString(init)).substr(0, 8);
		var reset = resets();
		return macro @:pos(init.pos) helder.view.Refresh.kept($made, $v{key}, $v{type}, $v{source}, $v{reset});
	}

	// whether the class or the function being typed is marked @:hot(reset)
	static function resets():Bool {
		inline function marked(meta:haxe.macro.Type.MetaAccess):Bool {
			var m = meta.extract(":hot");
			return Lambda.exists(m, e -> e.params != null && Lambda.exists(e.params, p -> switch p.expr {
				case EConst(CIdent("reset")) | EConst(CString("reset")): true;
				case _: false;
			}));
		}
		var c = Context.getLocalClass();
		if (c == null) return false;
		var cls = c.get();
		if (marked(cls.meta)) return true;
		var method = Context.getLocalMethod();
		if (method == null) return false;
		for (f in cls.statics.get().concat(cls.fields.get()))
			if (f.name == method && marked(f.meta)) return true;
		return false;
	}
	#elseif hxmc.dev
	// the signal s, its value the one the last build's signal of this key
	// had, when its initial value's source (init) is the same and it is not
	// reset each build; saved on each snapshot
	public static function kept<T>(s:helder.view.graph.Signal<T>, key:String, type:String, init:String, reset:Bool):helder.view.graph.Signal<T> {
		// (boxed: a null value is kept too; with the initial value's hash)
		var last:Null<{v:T, ?i:String}> = helder.dev.Hot.load(key, type);
		if (last != null && reset) last = null;
		if (last != null && last.i != null && last.i != init) {
			var line = "helder.dev: " + helder.dev.Hot.path() + (helder.dev.Hot.path() == "" ? "" : "/") + key + " reset: its initial value changed";
			Sys.stderr().writeString(line + "\n");
			last = null;
		}
		// (set before anything reads it: its value from the start)
		if (last != null) @:privateAccess s.node().value = last.v;
		helder.view.graph.Graph.onCleanup(helder.dev.Hot.onSnapshot(() -> helder.dev.Hot.save(key, {v: s.peek(), i: init}, type)));
		return s;
	}
	#end
}
