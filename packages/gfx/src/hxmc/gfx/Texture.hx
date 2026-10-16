package hxmc.gfx;

// A texture's handle (Buffer's conventions: an id into the device's table, 0 none)
abstract Texture(Int) {
	public static inline var NONE:Texture = cast 0;

	@:allow(hxmc.gfx) inline function new(id:Int)
		this = id;

	public inline function id():Int
		return this;
}
