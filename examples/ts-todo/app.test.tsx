// app.tsx's view mounted headless (helder/story's tree: helder.ui's layout,
// helder.text's own shaping, the same on every OS), its tree snapshotted
// (app.test.snap) before and after items are added and one is done. (A
// write commits at the loop's turn's end: flush() commits it here.) Its
// filters' shortcuts typed into it, in a headless window of its own.
import { flush } from "helder/view";
import { test, equals, snapshot } from "helder/test";
import { story, tree } from "helder/story";
import { headless, mount, rootOf, find, focus, press, actionName } from "helder/ui/actions";
import { App, Todo as TodoActions, todos, draft, add, filter } from "./app";
import { toggled } from "./todos";

const Todo = story({ name: "todo", render: () => <App/> });

test("empty", () => {
	snapshot("empty", tree(Todo, 480, 560));
});

test("two items, one done, the done ones shown", () => {
	for (const title of ["Buy milk", "Walk", "  "]) {
		draft(title);
		flush();
		add();
		flush();
	}
	equals(todos().map(i => i.title), ["Buy milk", "Walk"]);
	todos(toggled(todos(), 2));
	flush();
	snapshot("two", tree(Todo, 480, 560));
	filter("done");
	flush();
	snapshot("done", tree(Todo, 480, 560));
});

test("the filters' shortcuts: Todo's actions, from the text field", () => {
	const ui = headless(480, 560);
	const dispose = mount(ui, <App/>);
	focus(find(rootOf(ui), "draft"));
	press(ui, "ctrl-2");
	flush();
	equals(filter(), "active");
	press(ui, "ctrl-3");
	flush();
	equals(filter(), "done");
	equals(actionName(TodoActions.show("all")), "todo::Show");
	dispose();
	filter("all");
	flush();
});
