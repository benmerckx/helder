// TSX's holes through helder.markup's planner, as Haxe's markup's (helder.view
// DESIGN.md 3.3): a hole or an attribute that reads is bound with no () =>
// (a call, a read through a getter), a constant or a name is set once; a
// component's prop that reads (Read, helder's and the program's) is given as a
// function of its value; a signal's call is a read, a write or an update by
// its argument's type.
import { signal, memo, For, Show, Render, flush, Read } from "helder/view";
import { TestNode } from "./test-renderer";

const count = signal(1);
const names = signal(["a", "b"]);
const total = memo(() => names().length + count());
const label = "count";

// (its text a Read: the caller's expression, read when the component reads it)
function Badge(props: { text: Read<string>; tone: string }) {
	return <span class={props.tone}>{props.text()}</span>;
}

class Box {
	#n = 0;
	get reads(): number {
		return count() + this.#n;
	}
}
const box = new Box();

const root = TestNode.root("root");
Render.render(
	<div class={count() > 2 ? "big" : "small"} title={label}>
		<p>{label}: {count() * 2}, {total()} in all, {box.reads}</p>
		<Badge text={"n=" + count()} tone="info" />
		<For each={names}>{n => <i>{n().toUpperCase()}</i>}</For>
		<Show when={count() > 2} fallback={<b>few</b>}><b>many</b></Show>
		<button onClick={() => count(c => c + 1)}>+</button>
	</div>,
	root
);
console.log(root.toHtml());
root.fire("button", "onClick");
flush();
console.log(root.toHtml());
names([...names(), "c"]);
count(10);
flush();
console.log(root.toHtml(), total());
