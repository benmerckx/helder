package hxmc.gfx;

// a handle (Buffer)
abstract Sampler(Int) {
	@:allow(hxmc.gfx) inline function new(id:Int)
		this = id;

	public inline function id():Int
		return this;
}
