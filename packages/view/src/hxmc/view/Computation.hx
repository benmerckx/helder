package hxmc.view;

import hxmc.view.Memo;
import hxmc.view.Signal;

// a memo or an effect: it runs fn (a memo: its own run), tracking its
// sources (none yet: null)
class Computation extends Owner {
	final fn:Null<Void->Void>;
	public final isEffect:Bool;
	@:allow(hxmc.view) var state:State = Dirty;
	@:allow(hxmc.view) var sources:Null<Array<Source>> = null;
	var running = false;

	public function new(fn:Null<Void->Void>, isEffect:Bool) {
		super(Reactive.owner);
		this.fn = fn;
		this.isEffect = isEffect;
	}

	@:allow(hxmc.view) function update() {
		if (isDisposed) return;
		if (running) throw "hxmc.view: a computation depends on itself";
		clean();
		if (sources != null) {
			for (s in sources)
				s.observers.remove(this);
			sources.resize(0);
		}
		var savedOwner = Reactive.owner, savedCurrent = Reactive.current;
		Reactive.owner = this;
		Reactive.current = this;
		running = true;
		try {
			run();
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

	function run()
		fn();

	// s read for the first time since this last ran: added to its sources
	@:allow(hxmc.view) function depend(s:Source):Bool {
		if (sources == null) sources = [] else if (sources.contains(s)) return false;
		sources.push(s);
		return true;
	}

	function markObservers() {}

	@:allow(hxmc.view) function updateIfNecessary() {
		if (state == Check && sources != null) {
			for (s in sources.copy()) {
				if (Std.isOfType(s, MemoBase)) (cast s : MemoBase).updateIfNecessary();
				if (state == Dirty) break;
			}
		}
		if (state == Dirty) update();
		state = Clean;
	}

	override function detach() {
		if (sources == null) return;
		for (s in sources)
			s.observers.remove(this);
		sources = null;
	}
}
