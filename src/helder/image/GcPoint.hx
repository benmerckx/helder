package helder.image;

// A point where a long decode lets a collection in: natively, a decode run
// as a GC job (helder.jobs: the viewer's prefetch) shares the heap's
// collections, which wait for each thread's next safepoint (an allocation's
// slow path); a decoder's inner loops allocate nothing, so without these a
// 24 MP JPEG held every other thread's collection for up to 200 ms. Called
// once a row (or a macroblock row, an MCU row): one load when no
// collection is asked for. Nothing elsewhere.
class GcPoint {
	#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
	public static inline function poll()
		if (GcRequest.rt_gc_requested != 0) stop();

	// (the runtime's safepoint, a GC point: the caller's live references are
	// rooted across it, as at an allocation's slow path)
	static function stop()
		@:privateAccess hxmc.rt.Threads.preempt();
	#else
	public static inline function poll() {}
	#end

	// (poll, as a condition: true)
	public static inline function yes():Bool {
		poll();
		return true;
	}
}

#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
// (the runtime's flag, set while a collection waits for the other threads:
// read as a C variable, each read a load)
@:hxmc.c private extern class GcRequest {
	static final rt_gc_requested:Int;
}
#end
