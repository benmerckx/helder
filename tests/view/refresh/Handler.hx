package refresh;

// (RefreshTest: a generic class whose type parameters have constraints,
// typed after the signal of a class holding it is made)
class Handler<A:EnumValue, M:EnumValue> {
	final model:Model<A, M>;

	public function new(model:Model<A, M>)
		this.model = model;

	public function state(a:A):State<M>
		return Succes;
}

class Model<A:EnumValue, M:EnumValue> {
	public function new() {}
}

enum State<M:EnumValue> {
	Succes;
	Failure(m:M);
}
