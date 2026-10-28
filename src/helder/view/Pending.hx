package helder.view;

// A value read before it is ready (helder.asset's Asset.value while the
// file loads): what a reader throws, as Solid 2.0's NotReadyError. A
// computation that throws it renders nothing new (a region keeps what it
// showed, a text its text) and hands it to the nearest <Loading> boundary
// above it (Owner.onPending); it read its source first, so it runs again
// once the source is ready. A memo keeps it and its readers throw it in
// turn. With no boundary above it a computation renders nothing (logged
// in dev builds), as a component that throws it while it is made does.
class Pending extends haxe.Exception {
	public final source:Loadable;

	public function new(source:Loadable, message:String) {
		super(message);
		this.source = source;
	}
}

// what can be pending: its readiness (tracked), whether a value it has is
// being replaced (a reload in flight: tracked), and a function run once
// it is ready or has failed
interface Loadable {
	var ready(get, never):Bool;
	var refreshing(get, never):Bool;
	function whenReady(f:Void->Void):Void;
}
