package view.graph;

import helder.test.Test;
import helder.view.graph.Graph.*;

// equals-comparator-errors.test.ts (sync, without error boundaries)
private typedef User = {id:Int};

// (prev!.id === next!.id: a TypeError in JS on undefined)
private function sameId(prev:Null<User>, next:Null<User>):Bool {
	if (prev == null || next == null) throw "Cannot read properties of undefined (reading 'id')";
	return prev.id == next.id;
}

private function find(users:Array<User>):Null<User> {
	for (u in users)
		if (u.id == 1) return u;
	return null;
}

function tests() {
	afterEach(() -> flush());

	test("A4: the first commit never invokes a custom equals with an undefined previous value", () -> {
		var calls:Array<Array<Null<User>>> = [];
		var users = signal(([{id: 1}] : Array<User>));
		var value:Null<User> = null;
		root(_ -> {
			var selected = memo(() -> find(users()), {
				equals: (prev, next) -> {
					calls.push([prev, next]);
					sameId(prev, next);
				}
			});
			renderEffect(() -> selected(), v -> value = v);
		});
		flush();
		equals(value, {id: 1});
		equals(calls, []);
		users([{id: 1}]);
		flush();
		equals(calls, [[{id: 1}, {id: 1}]]);
	});

	// (adapted: the effect's error handler in place of the boundary)
	test("user effect on the errored memo does not fire with a bogus value", () -> {
		var values:Array<Null<User>> = [];
		var errors:Array<Dynamic> = [];
		var users = signal(([{id: 1}] : Array<User>));
		root(_ -> {
			var selected = memo(() -> find(users()), {equals: sameId});
			effect(() -> selected(), v -> values.push(v), e -> errors.push(e));
		});
		flush();
		equals(values, [{id: 1}]);
		users([]);
		flush();
		// the comparator threw before any commit: no effect run with null
		equals(values, [{id: 1}]);
		equals(errors.length, 1);
	});

	// (the halt and its logs are Solid's: only the error surfacing from the flush is ported)
	test("no boundary: halts loudly through REACTIVITY_HALTED, later writes report ignored", () -> {
		var log:Array<String> = [];
		var users = signal(([{id: 1}] : Array<User>));
		var beat = signal(0);
		root(_ -> {
			renderEffect(() -> beat(), v -> log.push('beat=$v'));
			var selected = memo(() -> find(users()), {equals: sameId});
			renderEffect(() -> {
				var s = selected();
				'sel=${s == null ? null : s.id}';
			}, v -> log.push(v));
		});
		flush();
		equals(log, ["beat=0", "sel=1"]);
		var e = throws(() -> {
			users([]);
			flush();
		});
		equals(e, "Cannot read properties of undefined (reading 'id')");
	});
}
