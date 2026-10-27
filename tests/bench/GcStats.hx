// The collector's counters, read in the process: hxmc.GcStats, the same
// natively and on wasm32 (collections, the bytes allocated on the GC heap
// since the start, large objects included, and the pauses: the collector's
// time and the wait for the world to stop). Elsewhere: nothing (zeros).
#if (target.name == "hxmc")
class GcStats {
	public static inline var TIMED = true;

	public static inline function collections():Int
		return hxmc.GcStats.collections();

	public static inline function majors():Int
		return hxmc.GcStats.majorCollections();

	public static inline function bytes():Float
		return hxmc.GcStats.bytesAllocated();

	public static inline function seconds():Float
		return hxmc.GcStats.totalPause();
}
#else
class GcStats {
	public static inline var TIMED = false;

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
