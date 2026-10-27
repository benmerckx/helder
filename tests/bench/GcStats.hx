// The collector's counters, read in the process (hxmc's runtime keeps them,
// RT_STATS prints them at exit): collections, the bytes allocated on the
// GC heap and the time spent collecting.
// - hxmc native (hxmc.rt.Gc): the bytes allocated in the nursery, counted
//   at each minor collection (with stats on, as RT_STATS turns it on) plus
//   the nursery's part in use; the seconds of minor and major collections.
// - hxmc wasm32 (hxmc.rt.wasm.Gc): no counts of bytes or time; the bytes are
//   the nursery's progress plus its size at each collection (it collects
//   when full), so within a chunk per collection; no time.
// - elsewhere: nothing (zeros).
#if (target.name == "hxmc" && !hxmc.wasm_gc && hxmc.target != "wasm32-wasi")
@:access(hxmc.rt.Gc)
class GcStats {
	public static inline var TIMED = true;

	public static function enable()
		hxmc.rt.Gc.stats = true;

	public static function disable()
		hxmc.rt.Gc.stats = false;

	public static function collections():Int
		return hxmc.rt.Gc.minors + hxmc.rt.Gc.majors;

	public static function majors():Int
		return hxmc.rt.Gc.majors;

	public static function bytes():Float {
		var p = hxmc.rt.Gc.yptr;
		var young:Float = cast hxmc.rt.Gc.youngBytes;
		var used:Float = p.isNull() ? 0.0 : cast p.diff(hxmc.rt.Gc.youngStart);
		return young + used;
	}

	public static function seconds():Float
		return hxmc.rt.Gc.minorSecs + hxmc.rt.Gc.majorSecs;
}
#elseif (target.name == "hxmc" && !hxmc.wasm_gc)
@:access(hxmc.rt.wasm.Gc)
class GcStats {
	public static inline var TIMED = false;

	// (the bytes so far: the nursery's sizes at the collections counted here)
	static var counted = 0;
	static var before = 0.0;

	public static function enable() {}

	public static function disable() {}

	public static function collections():Int
		return hxmc.rt.wasm.Gc.minors + hxmc.rt.wasm.Gc.majors;

	public static function majors():Int
		return hxmc.rt.wasm.Gc.majors;

	// (call often enough that few collections pass between two calls: each counts the size the nursery has now)
	public static function bytes():Float {
		var n = collections();
		if (n != counted) {
			before += (n - counted) * hxmc.rt.wasm.Gc.minorSize;
			counted = n;
		}
		var used:Float = cast hxmc.unsafe.Mem.tlsGet("rt_young_ptr").diff(hxmc.rt.wasm.Gc.youngStart);
		return before + used;
	}

	public static function seconds():Float
		return 0;
}
#else
class GcStats {
	public static inline var TIMED = false;

	public static function enable() {}

	public static function disable() {}

	public static function collections():Int
		return 0;

	public static function majors():Int
		return 0;

	public static function bytes():Float
		return 0;

	public static function seconds():Float
		return 0;
}
#end
