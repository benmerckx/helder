package hxmc.gfx;

// Handles: Int ids (index + 1; 0 is none) into the device's tables. No
// finalizers: a resource lives as long as its device.
abstract Buffer(Int) {
	public static inline var NONE:Buffer = cast 0;

	@:allow(hxmc.gfx) inline function new(id:Int)
		this = id;

	public inline function id():Int
		return this;
}
