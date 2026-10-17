package hxmc.view;

// what computations read: signals and memos
interface Source {
	// (null: none yet)
	var observers(default, null):Null<Array<Computation>>;
}
