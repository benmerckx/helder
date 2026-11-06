// app.tsx's view mounted headless (helder/story's tree: helder.ui's layout,
// helder.text's own shaping, the same on every OS), its tree snapshotted
// (app.test.snap) before and after items are added and one is done. (A
// write commits at the loop's turn's end: flush() commits it here.)
import { flush } from "helder/view";
import { test, equals, snapshot } from "helder/test";
import { story, tree } from "helder/story";
import { App, todos, draft, add, filter } from "./app";
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
