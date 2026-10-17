package hxmc.view;

import hxmc.view.Memo;
import hxmc.view.Signal;

// a memo or an effect: it runs fn, tracking its sources
class Computation extends Owner {
	final fn:Void->Void;
	public final isEffect:Bool;
	@:allow(hxmc.view) var state:State = Dirty;
	@:allow(hxmc.view) var sources:Array<Source> = [];
	var running = false;

	public function new(fn:Void->Void, isEffect:Bool) {
		super(Reactive.owner);
		this.fn = fn;
		this.isEffect = isEffect;
	}

	@:allow(hxmc.view) function update() {
		if (isDisposed) return;
		if (running) throw "hxmc.view: a computation depends on itself";
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
			// (an ErrorBoundary above takes it)
			if (!handle(e)) throw e;
			return;
		}
		running = false;
		Reactive.owner = savedOwner;
		Reactive.current = savedCurrent;
		state = Clean;
	}

	// a source changed (Dirty) or may have (Check)
	@:allow(hxmc.view) function stale(s:State) {
		if ((state : Int) >= (s : Int)) return;
		var was = state;
		state = s;
		if (was == Clean) {
			if (isEffect) Reactive.schedule(this);
			markObservers();
		}
	}

	function markObservers() {}

	@:allow(hxmc.view) function updateIfNecessary() {
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
