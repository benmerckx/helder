package store;

import hxmc.dev.Hot;

// A small store, written as a third-party state library would be (it knows
// nothing of hxmc.view): a state, changed by functions, read by listeners.
// It is reload-safe under `hxmc dev` with Hot's public calls only: the three
// lines in the constructor, and `create`, which keys a store by where it is
// made and hashes its state's type, so that its users write nothing.
// (docs/dev.md, "State libraries"; tested by packages/os/test/HotTest.hx)
class Store<S> {
	public var state(default, null):S;

	final listeners:Array<S->Void> = [];

	public function new(key:String, initial:S, type:String) {
		var kept:Null<S> = Hot.load(key, type);
		state = kept != null ? kept : initial;
		Hot.onSnapshot(() -> Hot.save(key, state, type));
	}

	// a store of initial's type, keyed by the place it is made (`var cart =
	// Store.create(...)`: Type.method.cart; Hot.here() written here would be this place)
	public static macro function create(initial:haxe.macro.Expr):haxe.macro.Expr
		return macro new store.Store($v{hxmc.dev.HotMacro.here(haxe.macro.Context.currentPos())}, $initial, hxmc.dev.Hot.typeOf($initial));

	public function update(f:S->S) {
		state = f(state);
		for (l in listeners)
			l(state);
	}

	public function listen(l:S->Void)
		listeners.push(l);
}
