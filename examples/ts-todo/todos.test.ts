// todos.ts's functions (helder test examples/ts-todo: natively and as wasm32-wasi)
import { describe, test, beforeEach, equals, notEquals, assert } from "helder/test";
import { Item, added, removed, toggled, shown, left } from "./todos";

describe("todos", () => {
	let list: Item[] = [];
	beforeEach(() => {
		list = added(added([], 1, "Buy milk"), 2, " Walk ");
	});

	test("added: trimmed, at the end, not done", () => {
		equals(list, [{ id: 1, title: "Buy milk", done: false }, { id: 2, title: "Walk", done: false }]);
	});

	test("added: a blank title leaves the list as it is", () => {
		assert(added(list, 3, "   ") === list);
	});

	test("toggled and removed by id", () => {
		const t = toggled(list, 2);
		equals(t.map(i => i.done), [false, true]);
		notEquals(t, list);
		equals(removed(t, 1).map(i => i.title), ["Walk"]);
	});

	test("shown by filter", () => {
		const t = toggled(list, 1);
		equals(shown(t, "all").length, 2);
		equals(shown(t, "active").map(i => i.id), [2]);
		equals(shown(t, "done").map(i => i.id), [1]);
	});

	test("left", () => {
		equals(left(list), "2 items left");
		equals(left(toggled(list, 1)), "1 item left");
		equals(left([]), "0 items left");
	});

	test("an async test", async () => {
		const later = await new Promise<Item[]>(resolve => setTimeout(() => resolve(toggled(list, 2)), 1));
		equals(left(later), "1 item left");
	});
});
