// The todo list's screens (`helder studio examples/ts-todo`: a flow a
// name's part before its "/"): empty, with three items, filtered to the
// done ones, at the window's size; and on a phone (a story's size without
// width and height), its store screenshot (and helder.run's). The studio
// runs every screen in one program, so each story has a store of its own
// (a module's signals are every screen's).
import { story } from "helder/story";
import { App, store } from "./app";
import type { Item } from "./todos";

const three: Item[] = [
	{ id: 1, title: "Buy milk", done: false },
	{ id: 2, title: "Walk the dog", done: true },
	{ id: 3, title: "Call Ana", done: false },
];

export const empty = story({ name: "Todo/Empty", width: 480, height: 560, render: () => <App store={store()}/> });

export const items = story({ name: "Todo/Three items", width: 480, height: 560, render: () => <App store={store(three)}/> });

export const done = story({ name: "Todo/Done", width: 480, height: 560, render: () => <App store={store(three, "done")}/> });

export const phone = story({ name: "Phone/Three items", store: true, caption: "Keep a list of things to do", render: () => <App store={store(three)}/> });
