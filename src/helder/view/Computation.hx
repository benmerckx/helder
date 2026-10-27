package helder.view;

import helder.view.Memo;
import helder.view.Signal;

// a memo or an effect: it runs fn (a memo: its own run), tracking its
// sources (none yet: null)
class Computation extends Owner {
	final fn:Null<Void->Void>;
	public final isEffect:Bool;
	@:allow(helder.view) var state:State = Dirty;
	@:allow(helder.view) var sources:Null<Array<Source>> = null;
	var running = false;
	#if hxmc.dev
	// (hxmc dev: the scope of the keys made when it runs, its own: helder.view.Refresh)
	var hotPath:Null<String> = null;
	#end

	public function new(fn:Null<Void->Void>, isEffect:Bool) {
		super(Reactive.owner);
		this.fn = fn;
		this.isEffect = isEffect;
	}

	@:allow(helder.view) function update() {
		if (isDisposed) return;
		if (running) throw "helder.view: a computation depends on itself";
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
			#if hxmc.dev
			if (hotPath == null) helder.dev.Hot.scope("$c", () -> {
				hotPath = helder.dev.Hot.path();
				run();
			}) else helder.dev.Hot.at(hotPath, run);
			#else
			run();
			#end
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
	@:allow(helder.view) function stale(s:State) {
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
	@:allow(helder.view) function depend(s:Source):Bool {
		if (sources == null) sources = [] else if (sources.contains(s)) return false;
		sources.push(s);
		return true;
	}

	function markObservers() {}

	@:allow(helder.view) function updateIfNecessary() {
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
