// title: Todo in TypeScript
// summary: The todo list in TSX: signals, For keeping a row per item, a text field, checkboxes and filters, components of its own
// tags: typescript, ui, view, text input
// demo: canvas 480x560
// The todo list in TypeScript, in a window: its view (app.tsx) holds the
// state in signals and changes it with todos.ts's functions. The items are
// data, so under `helder dev` an edit reloads it with the list as it was
// (fast refresh keeps signals of data). Its tests, `helder test
// examples/ts-todo`: todos.test.ts (the functions), app.test.tsx (the
// view mounted headless, typed into and clicked, its tree snapshotted).
// (examples/todo in Haxe.)
import { UiWindow, Surface } from "helder/ui";
import { App } from "./app";

UiWindow.run(
	<Surface title="Todo" width={480} height={560}>
		<App/>
	</Surface>
);
