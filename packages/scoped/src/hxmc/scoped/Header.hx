package hxmc.scoped;

// The headers of Slices, Grows and Strs carry a magic word. Freed memory is
// overwritten in debug builds (-D scoped_debug: Memory.leaveSlow), so a value
// used after its scope has ended fails here with a message instead of
// reading what has been allocated since. Without the define, check is the
// address unchanged.
class Header {
	public static inline var MAGIC = 0x5C0BED;

	public static inline function check(h:Int, at:Int):Int {
		#if scoped_debug
		if (Memory.getI32(h + at) != MAGIC)
			Memory.fail("a scoped value used after its scope ended");
		#end
		return h;
	}
}
