package helder.devtools;

// The collector's counters, the one place they are read: hxmc.GcStats, the
// same natively and on wasm32 (collections, the bytes allocated on the GC
// heap since the start, large objects included, and the seconds paused:
// collecting and waiting for the world to stop, kept whether or not the
// runtime's RT_STATS is on). Elsewhere zeros.
#if (target.name == "hxmc")
class GcCounters {
	public static inline var TIMED = true;

	public static inline function collections():Int
		return hxmc.GcStats.collections();

	public static inline function bytes():Float
		return hxmc.GcStats.bytesAllocated();

	public static inline function seconds():Float
		return hxmc.GcStats.totalPause();
}
#else
class GcCounters {
	public static inline var TIMED = false;

	public static inline function collections():Int
		return 0;

	public static inline function bytes():Float
		return 0;

	public static inline function seconds():Float
		return 0;
}
#end
