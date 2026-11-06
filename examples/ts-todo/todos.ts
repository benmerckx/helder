// The todo list's data and what changes it, plain functions of values (the
// view's signals hold them: app.tsx), tested by todos.test.ts.
export type Item = { id: number; title: string; done: boolean };

// the list with an item of this title at the end (unchanged when it is blank)
export function added(list: Item[], id: number, title: string): Item[] {
	const t = title.trim();
	return t === "" ? list : [...list, { id, title: t, done: false }];
}

export function removed(list: Item[], id: number): Item[] {
	return list.filter(x => x.id !== id);
}

export function toggled(list: Item[], id: number): Item[] {
	return list.map(x => x.id === id ? { ...x, done: !x.done } : x);
}

export function shown(list: Item[], filter: string): Item[] {
	return list.filter(i => filter === "active" ? !i.done : filter === "done" ? i.done : true);
}

export function left(list: Item[]): string {
	const n = list.filter(i => !i.done).length;
	return n === 1 ? "1 item left" : n + " items left";
}
