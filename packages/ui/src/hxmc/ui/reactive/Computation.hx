package hxmc.ui.reactive;

import hxmc.ui.reactive.Memo;
import hxmc.ui.reactive.Signal;

// a memo or an effect: it runs fn, tracking its sources
class Computation extends Owner {
	final fn:Void->Void;
	public final isEffect:Bool;
	@:allow(hxmc.ui.reactive) var state:State = Dirty;
	@:allow(hxmc.ui.reactive) var sources:Array<Source> = [];
	var running = false;

	public function new(fn:Void->Void, isEffect:Bool) {
		super(Reactive.owner);
		this.fn = fn;
		this.isEffect = isEffect;
	}

	@:allow(hxmc.ui.reactive) function update() {
		if (isDisposed) return;
		if (running) throw "hxmc.ui.reactive: a computation depends on itself";
		clean();
		for (s in sources)
			s.observers.remove(this);
		sources = [];
		var savedOwner = Reactive.owner, savedCurrent = Reactive.current;
		Reactive.owner = this;
		Reactive.current = this;
		running = true;
		try {
			fn();
		} catch (e:Dynamic) {
			running = false;
			Reactive.owner = savedOwner;
			Reactive.current = savedCurrent;
			state = Clean;
			throw e;
		}
		running = false;
		Reactive.owner = savedOwner;
		Reactive.current = savedCurrent;
		state = Clean;
	}

	// a source changed (Dirty) or may have (Check)
	@:allow(hxmc.ui.reactive) function stale(s:State) {
		if ((state : Int) >= (s : Int)) return;
		var was = state;
		state = s;
		if (was == Clean) {
			if (isEffect) Reactive.schedule(this);
			markObservers();
		}
	}

	function markObservers() {}

	@:allow(hxmc.ui.reactive) function updateIfNecessary() {
		if (state == Check) {
			for (s in sources.copy()) {
				if (Std.isOfType(s, MemoBase)) (cast s : MemoBase).updateIfNecessary();
				if (state == Dirty) break;
			}
		}
		if (state == Dirty) update();
		state = Clean;
	}

	override function detach() {
		for (s in sources)
			s.observers.remove(this);
		sources = [];
	}
}
