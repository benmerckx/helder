// The todo list's screens (`helder studio examples/ts-todo`: a flow a
// name's part before its "/"): empty, with three items, filtered to the
// done ones, at the window's size; and on a phone (a story's size without
// width and height). The studio runs each screen in a process of its own,
// so each has the list its story sets.
import { story } from "helder/story";
import { App, todos, filter } from "./app";
import type { Item } from "./todos";

const three: Item[] = [
	{ id: 1, title: "Buy milk", done: false },
	{ id: 2, title: "Walk the dog", done: true },
	{ id: 3, title: "Call Ana", done: false },
];

export const empty = story({ name: "Todo/Empty", width: 480, height: 560, render: () => <App/> });

export const items = story({
	name: "Todo/Three items",
	width: 480,
	height: 560,
	render: () => {
		todos(three);
		return <App/>;
	},
});

export const done = story({
	name: "Todo/Done",
	width: 480,
	height: 560,
	render: () => {
		todos(three);
		filter("done");
		return <App/>;
	},
});

export const phone = story({
	name: "Phone/Three items",
	render: () => {
		todos(three);
		return <App/>;
	},
});
