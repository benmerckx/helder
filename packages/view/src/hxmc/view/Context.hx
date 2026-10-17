package hxmc.view;

// A value passed down the ownership tree without props (Solid's context):
// Reactive.provide (or the Provider component) sets it for what runs inside,
// Reactive.use reads the nearest one (else the default).
class Context<T> {
	@:allow(hxmc.view) final id:Int = nextId++;
	public final defaultValue:T;

	static var nextId = 1;

	public function new(defaultValue:T)
		this.defaultValue = defaultValue;
}
