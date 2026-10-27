package helder.devtools;

// The collector's counters, the one place they are read (as
// tests/bench/GcStats.hx reads them; hxmc's coming hxmc.GcStats replaces
// this once a nightly has it): collections, the bytes allocated in the
// nursery (what the young generation counts at each minor collection, plus
// its part in use: not the objects allocated straight into the old space)
// and the seconds spent collecting. Natively the seconds need the runtime's
// stats on (enable: RT_STATS's, whose lines on a major collection and at
// exit go to stderr while they are on). wasm32: collections and bytes
// within a nursery per collection, no time; elsewhere zeros.
#if (target.name == "hxmc" && !hxmc.wasm_gc && hxmc.target != "wasm32-wasi")
@:access(hxmc.rt.Gc)
class GcCounters {
	public static inline var TIMED = true;

	// (RT_STATS's own setting, given back)
	static var was = false;

	public static function enable(on:Bool) {
		if (on) was = hxmc.rt.Gc.stats;
		hxmc.rt.Gc.stats = on || was;
	}

	public static inline function collections():Int
		return hxmc.rt.Gc.minors + hxmc.rt.Gc.majors;

	public static function bytes():Float {
		var p = hxmc.rt.Gc.yptr;
		var young:Float = cast hxmc.rt.Gc.youngBytes;
		var used:Float = p.isNull() ? 0.0 : cast p.diff(hxmc.rt.Gc.youngStart);
		return young + used;
	}

	public static inline function seconds():Float
		return hxmc.rt.Gc.minorSecs + hxmc.rt.Gc.majorSecs;
}
#elseif (target.name == "hxmc" && !hxmc.wasm_gc)
@:access(hxmc.rt.wasm.Gc)
class GcCounters {
	public static inline var TIMED = false;

	static var counted = 0;
	static var before = 0.0;

	public static function enable(on:Bool) {}

	public static inline function collections():Int
		return hxmc.rt.wasm.Gc.minors + hxmc.rt.wasm.Gc.majors;

	public static function bytes():Float {
		var n = collections();
		if (n != counted) {
			before += (n - counted) * hxmc.rt.wasm.Gc.minorSize;
			counted = n;
		}
		var used:Float = cast hxmc.unsafe.Mem.tlsGet("rt_young_ptr").diff(hxmc.rt.wasm.Gc.youngStart);
		return before + used;
	}

	public static inline function seconds():Float
		return 0;
}
#else
class GcCounters {
	public static inline var TIMED = false;

	public static function enable(on:Bool) {}

	public static inline function collections():Int
		return 0;

	public static inline function bytes():Float
		return 0;

	public static inline function seconds():Float
		return 0;
}
#end
