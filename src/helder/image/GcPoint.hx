package helder.image;

// A point where a long decode lets a collection in: natively, a decode run
// as a GC job (helder.jobs: the viewer's prefetch) shares the heap's
// collections, which wait for each thread's next safepoint (an allocation's
// slow path); a decoder's inner loops allocate nothing, so without these a
// 24 MP JPEG held every other thread's collection for up to 200 ms. Called
// once a row (or a macroblock row, an MCU row): one atomic load when no
// collection is asked for. Nothing elsewhere.
class GcPoint {
	#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
	public static inline function poll()
		if (requested()) stop();

	@:hxmc.unsafe static inline function requested():Bool
		return hxmc.unsafe.Atomic.load32(hxmc.unsafe.Mem.sym("rt_gc_requested")) != 0;

	// (a GC point: @:hxmc.collects, so that the caller's live references are
	// rooted across it, as at an allocation's slow path; the stop itself the
	// runtime's)
	@:hxmc.collects static function stop()
		stopHere();

	@:hxmc.unsafe static function stopHere()
		@:privateAccess hxmc.rt.Threads.safepointSlow();
	#else
	public static inline function poll() {}
	#end

	// (poll, as a condition: true)
	public static inline function yes():Bool {
		poll();
		return true;
	}
}
