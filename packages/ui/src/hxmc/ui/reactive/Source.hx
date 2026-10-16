package hxmc.ui.reactive;

// what computations read: signals and memos
interface Source {
	var observers(default, null):Array<Computation>;
}
