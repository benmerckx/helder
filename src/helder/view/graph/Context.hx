package helder.view.graph;

// A value passed down the ownership tree (Graph.context, use, provide,
// setContext).
class Context<T> {
	@:allow(helder.view.graph) final id:Int = nextId++;
	public final defaultValue:Null<T>;
	// (false: reading it where none is provided is an error)
	public final hasDefault:Bool;

	static var nextId = 1;

	public function new(defaultValue:Null<T>, hasDefault:Bool) {
		this.defaultValue = defaultValue;
		this.hasDefault = hasDefault;
	}
}
