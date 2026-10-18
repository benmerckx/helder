package hxmc.view;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

// Fast refresh for hxmc.view under `hxmc dev` (-D hxmc.dev; docs/dev.md),
// written on hxmc.dev.Hot's public calls only, as any state library would
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
// Without -D hxmc.dev none of this is compiled (Reactive.signal is `new
// Signal(value)`).
class Refresh {
	#if macro
	// Reactive.signal(value) under -D hxmc.dev
	public static function signal(value:Expr):Expr {
		var key = hxmc.dev.HotMacro.here(Context.currentPos());
		var type = hxmc.dev.HotMacro.hash(Context.typeof(value));
		// (a value whose type is not known yet: the type expected, `var s:Signal<Array<String>> = signal([])`)
		if (type == "") {
			var expected = Context.getExpectedType();
			if (expected != null)
				switch Context.follow(expected) {
					case TInst(_.get() => {pack: ["hxmc", "view"], name: "Signal"}, [t]): type = hxmc.dev.HotMacro.hash(t);
					case _:
				}
		}
		return macro @:pos(value.pos) hxmc.view.Refresh.kept($value, $v{key}, $v{type});
	}
	#elseif hxmc.dev
	// a signal of value, or of the value the last build's signal of this key had
	public static function kept<T>(value:T, key:String, type:String):Signal<T> {
		// (boxed: a null value is kept too)
		var last:Null<{v:T}> = hxmc.dev.Hot.load(key, type);
		var s = new Signal<T>(last != null ? last.v : value);
		Reactive.onCleanup(hxmc.dev.Hot.onSnapshot(() -> hxmc.dev.Hot.save(key, {v: s.peek()}, type)));
		return s;
	}
	#end
}
