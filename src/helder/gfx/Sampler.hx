package helder.gfx;

// a handle (Buffer)
abstract Sampler(Int) {
	@:allow(helder.gfx) inline function new(id:Int)
		this = id;

	public inline function id():Int
		return this;
}
